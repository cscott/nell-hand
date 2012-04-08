UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

# set aside 20% of the training data for evaluation.
TRAINAMT=5
# total # of mixtures
MIX=16
# total # of allographs to train
ALLOGRAPHS=4

#SYMBOLS=$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS)
SYMBOLS=$(UPPER_LETTERS)

ALL_SCRIPT=$(foreach l,$(SYMBOLS),parm/$(l).scr)
ALL_LABEL=$(foreach l,$(SYMBOLS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(SYMBOLS),html/$(l).html)

all: accuracy qual
accuracy: $(foreach n,9 X Z 10 11 12,hmm$(n)/accuracy.txt)
qual: $(foreach n,9 X Z 10 11 12,hmm$(n)/accuracy-qual.txt)

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr parm/%-qual.scr: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -T $(TRAINAMT) -H html/$*.html -A $(ALLOGRAPHS) \
		-M parm/$*.mlf -P parm/$* -S parm/$*.scr -Q parm/$*-qual.scr \
		$<

# helper: dump parameter file
parm/%.out: parm/%.htk
	HList -C htk-config -t $<

parm/train.scr: $(ALL_SCRIPT)
	cat $(ALL_SCRIPT) > $@
parm/qual.scr: $(foreach l,$(SYMBOLS),parm/$(l)-qual.scr)
	cat $^ > $@

parm/all.mlf: $(ALL_LABEL)
	echo "#!MLF!#" > $@
	cat $^ | grep -v -F '#!MLF!#' >> $@
parm/allograph.mlf parm/all2.mlf: $(ALL_LABEL)
ifeq ($(ALLOGRAPHS),1)
	$(MAKE) parm/all.mlf
	cp parm/all.mlf parm/allograph.mlf
	cp parm/all.mlf parm/all2.mlf
else
	echo "#!MLF!#" > parm/allograph.mlf
	cat $(foreach l,$^,$(l).allograph) | grep -v -F '#!MLF!#' >> parm/allograph.mlf
	echo "DL" > rml.hled
	HLEd -i parm/all2.mlf rml.hled parm/allograph.mlf
	$(RM) rml.hled
endif

parm/gram-single: Makefile
	echo "( $(firstword $(SYMBOLS)) $(patsubst %,|%,$(wordlist 2,$(words $(SYMBOLS)),$(SYMBOLS))) )" > $@.tmp
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi
parm/gram-multi: Makefile
	echo "( < $(firstword $(SYMBOLS)) $(patsubst %,|%,$(wordlist 2,$(words $(SYMBOLS)),$(SYMBOLS))) > )" > $@.tmp
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi
parm/wdnet%: parm/gram%
	HParse $< $@
parm/symbols: Makefile
	$(RM) -f $@.tmp
	touch $@.tmp
ifeq ($(ALLOGRAPHS),1)
	for s in $(SYMBOLS); do \
	  echo $$s >> $@.tmp ; \
	done
else
	for s in $(SYMBOLS); do \
	  for a in `seq 1 $(ALLOGRAPHS)`; do \
	    echo $$s$$a >> $@.tmp ; \
	  done ; \
	done
endif
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi
parm/words: Makefile
	$(RM) -f $@.tmp
	touch $@.tmp
	for s in $(SYMBOLS); do \
	  echo $$s >> $@.tmp ; \
	done
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi
parm/dict: Makefile
	$(RM) -f $@.tmp
	touch $@.tmp
ifeq ($(ALLOGRAPHS),1)
	for s in $(SYMBOLS); do \
	  echo $$s $$s >> $@.tmp ; \
	done
else
	for s in $(SYMBOLS); do \
	  for a in `seq 1 $(ALLOGRAPHS)`; do \
	    echo $$s $$s$$a >> $@.tmp ; \
	  done ; \
	done
endif
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi

# test word network
gen-%: parm/wdnet% hmm0/symbols
	HSGen $< hmm0/symbols

# global mean/variance computation
hmm0/proto hmm0/vFloors: htk-config proto parm/train.scr
	mkdir -p hmm0
	HCompV -C htk-config -f 0.01 -m -S parm/train.scr -M hmm0 proto

# create flat-start monophone models
hmm0/macros: hmm0/vFloors
	mkdir -p hmm0
	echo "~o <VecSize> 30 <USER_D_A>" > $@
	cat $< >> $@
hmm0/hmmdefs: hmm0/proto
	mkdir -p hmm0
	$(RM) -f $@
	touch $@
ifeq ($(ALLOGRAPHS),1)
	for s in $(SYMBOLS); do \
	  echo '~h "'$$s'"' >> $@ ; \
	  sed -e '0,/^~h/d' < hmm0/proto >> $@ ; \
	done
else
	for s in $(SYMBOLS); do \
	  for a in `seq 1 $(ALLOGRAPHS)`; do \
	    echo '~h "'$$s$$a'"' >> $@ ; \
	    sed -e '0,/^~h/d' < hmm0/proto >> $@ ; \
	  done ; \
	done
endif

hmm1/hmmdefs: htk-config hmm0/macros hmm0/hmmdefs parm/symbols parm/allograph.mlf
	mkdir -p hmm1
	HERest -C htk-config -I parm/allograph.mlf \
	  -S parm/train.scr -H hmm0/macros -H hmm0/hmmdefs -M hmm1 parm/symbols
hmm2/hmmdefs: htk-config hmm1/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm2
	HVite -C htk-config -H hmm1/macros -H hmm1/hmmdefs -S parm/train.scr \
              -i hmm2/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm2/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1/macros -H hmm1/hmmdefs -M hmm2 parm/symbols
hmm3/hmmdefs: htk-config hmm2/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm3
	HVite -C htk-config -H hmm2/macros -H hmm2/hmmdefs -S parm/train.scr \
              -i hmm3/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm3/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm2/macros -H hmm2/hmmdefs -M hmm3 parm/symbols
hmm4/hmmdefs: htk-config hmm3/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm4
	HVite -C htk-config -H hmm3/macros -H hmm3/hmmdefs -S parm/train.scr \
              -i hmm4/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm4/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm3/macros -H hmm3/hmmdefs -M hmm4 parm/symbols
hmm5/hmmdefs: htk-config hmm4/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm5
	HVite -C htk-config -H hmm4/macros -H hmm4/hmmdefs -S parm/train.scr \
              -i hmm5/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm5/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm4/macros -H hmm4/hmmdefs -M hmm5 parm/symbols
hmm6/hmmdefs: htk-config hmm5/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm6
	HVite -C htk-config -H hmm5/macros -H hmm5/hmmdefs -S parm/train.scr \
              -i hmm6/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm6/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm5/macros -H hmm5/hmmdefs -M hmm6 parm/symbols
hmm7/hmmdefs: htk-config hmm6/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm7
	HVite -C htk-config -H hmm6/macros -H hmm6/hmmdefs -S parm/train.scr \
              -i hmm7/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm7/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm6/macros -H hmm6/hmmdefs -M hmm7 parm/symbols
hmm8/hmmdefs: htk-config hmm7/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm8
	HVite -C htk-config -H hmm7/macros -H hmm7/hmmdefs -S parm/train.scr \
              -i hmm8/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm8/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm7/macros -H hmm7/hmmdefs -M hmm8 parm/symbols
hmm9/hmmdefs: htk-config hmm8/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm9
	HVite -C htk-config -H hmm8/macros -H hmm8/hmmdefs -S parm/train.scr \
              -i hmm9/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm9/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm8/macros -H hmm8/hmmdefs -M hmm9 parm/symbols

# scale up to $(MIX) mixtures... slowly
hmmA/hmmdefs: htk-config hmm9/hmmdefs parm/symbols
	mkdir -p hmmA
	HERest -C htk-config -I hmm9/aligned.mlf -s hmmA/stats \
	  -S parm/train.scr -H hmm9/macros -H hmm9/hmmdefs -M hmmA parm/symbols
	echo "LS hmmA/stats" > hmmA/mix.hed
	echo "PS $(MIX) 0.2 5" >> hmmA/mix.hed
	HHEd -C htk-config -H hmm9/macros -H hmm9/hmmdefs -M hmmA \
	  hmmA/mix.hed parm/symbols
hmmB/hmmdefs: htk-config hmmA/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmB
	HERest -C htk-config -I hmm9/aligned.mlf \
	  -S parm/train.scr -H hmmA/macros -H hmmA/hmmdefs -M hmmB parm/symbols
hmmC/hmmdefs: htk-config hmmB/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmC
	HVite -C htk-config -H hmmB/macros -H hmmB/hmmdefs -S parm/train.scr \
              -i hmmC/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmC/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmB/macros -H hmmB/hmmdefs -M hmmC parm/symbols
hmmD/hmmdefs: htk-config hmmC/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmD
	HVite -C htk-config -H hmmC/macros -H hmmC/hmmdefs -S parm/train.scr \
              -i hmmD/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmD/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmC/macros -H hmmC/hmmdefs -M hmmD parm/symbols

hmmE/hmmdefs: htk-config hmmD/hmmdefs parm/symbols
	mkdir -p hmmE
	HERest -C htk-config -I hmmD/aligned.mlf -s hmmE/stats \
	  -S parm/train.scr -H hmmD/macros -H hmmD/hmmdefs -M hmmE parm/symbols
	echo "LS hmmE/stats" > hmmE/mix.hed
	echo "PS $(MIX) 0.2 4" >> hmmE/mix.hed
	HHEd -C htk-config -H hmmD/macros -H hmmD/hmmdefs -M hmmE \
	  hmmE/mix.hed parm/symbols
hmmF/hmmdefs: htk-config hmmE/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmF
	HERest -C htk-config -I hmmD/aligned.mlf \
	  -S parm/train.scr -H hmmE/macros -H hmmE/hmmdefs -M hmmF parm/symbols
hmmG/hmmdefs: htk-config hmmF/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmG
	HVite -C htk-config -H hmmF/macros -H hmmF/hmmdefs -S parm/train.scr \
              -i hmmG/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmG/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmF/macros -H hmmF/hmmdefs -M hmmG parm/symbols
hmmH/hmmdefs: htk-config hmmG/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmH
	HVite -C htk-config -H hmmG/macros -H hmmG/hmmdefs -S parm/train.scr \
              -i hmmH/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmH/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmG/macros -H hmmG/hmmdefs -M hmmH parm/symbols

hmmI/hmmdefs: htk-config hmmH/hmmdefs parm/symbols
	mkdir -p hmmI
	HERest -C htk-config -I hmmH/aligned.mlf -s hmmI/stats \
	  -S parm/train.scr -H hmmH/macros -H hmmH/hmmdefs -M hmmI parm/symbols
	echo "LS hmmI/stats" > hmmI/mix.hed
	echo "PS $(MIX) 0.2 3" >> hmmI/mix.hed
	HHEd -C htk-config -H hmmH/macros -H hmmH/hmmdefs -M hmmI \
	  hmmI/mix.hed parm/symbols
hmmJ/hmmdefs: htk-config hmmI/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmJ
	HERest -C htk-config -I hmmH/aligned.mlf \
	  -S parm/train.scr -H hmmI/macros -H hmmI/hmmdefs -M hmmJ parm/symbols
hmmK/hmmdefs: htk-config hmmJ/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmK
	HVite -C htk-config -H hmmJ/macros -H hmmJ/hmmdefs -S parm/train.scr \
              -i hmmK/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmK/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmJ/macros -H hmmJ/hmmdefs -M hmmK parm/symbols
hmmL/hmmdefs: htk-config hmmK/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmL
	HVite -C htk-config -H hmmK/macros -H hmmK/hmmdefs -S parm/train.scr \
              -i hmmL/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmL/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmK/macros -H hmmK/hmmdefs -M hmmL parm/symbols

hmmM/hmmdefs: htk-config hmmL/hmmdefs parm/symbols
	mkdir -p hmmM
	HERest -C htk-config -I hmmL/aligned.mlf -s hmmM/stats \
	  -S parm/train.scr -H hmmL/macros -H hmmL/hmmdefs -M hmmM parm/symbols
	echo "LS hmmM/stats" > hmmM/mix.hed
	echo "PS $(MIX) 0.2 2" >> hmmM/mix.hed
	HHEd -C htk-config -H hmmL/macros -H hmmL/hmmdefs -M hmmM \
	  hmmM/mix.hed parm/symbols
hmmN/hmmdefs: htk-config hmmM/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmN
	HERest -C htk-config -I hmmL/aligned.mlf \
	  -S parm/train.scr -H hmmM/macros -H hmmM/hmmdefs -M hmmN parm/symbols
hmmO/hmmdefs: htk-config hmmN/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmO
	HVite -C htk-config -H hmmN/macros -H hmmN/hmmdefs -S parm/train.scr \
              -i hmmO/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmO/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmN/macros -H hmmN/hmmdefs -M hmmO parm/symbols
hmmP/hmmdefs: htk-config hmmO/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmP
	HVite -C htk-config -H hmmO/macros -H hmmO/hmmdefs -S parm/train.scr \
              -i hmmP/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmP/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmO/macros -H hmmO/hmmdefs -M hmmP parm/symbols

hmmQ/hmmdefs: htk-config hmmP/hmmdefs parm/symbols
	mkdir -p hmmQ
	HERest -C htk-config -I hmmP/aligned.mlf -s hmmQ/stats \
	  -S parm/train.scr -H hmmP/macros -H hmmP/hmmdefs -M hmmQ parm/symbols
	echo "LS hmmQ/stats" > hmmQ/mix.hed
	echo "PS $(MIX) 0.2 1" >> hmmQ/mix.hed
	HHEd -C htk-config -H hmmP/macros -H hmmP/hmmdefs -M hmmQ \
	  hmmQ/mix.hed parm/symbols
hmmR/hmmdefs: htk-config hmmQ/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmR
	HERest -C htk-config -I hmmP/aligned.mlf \
	  -S parm/train.scr -H hmmQ/macros -H hmmQ/hmmdefs -M hmmR parm/symbols
hmmS/hmmdefs: htk-config hmmR/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmS
	HVite -C htk-config -H hmmR/macros -H hmmR/hmmdefs -S parm/train.scr \
              -i hmmS/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmS/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmR/macros -H hmmR/hmmdefs -M hmmS parm/symbols
hmmT/hmmdefs: htk-config hmmS/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmT
	HVite -C htk-config -H hmmS/macros -H hmmS/hmmdefs -S parm/train.scr \
              -i hmmT/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmT/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmS/macros -H hmmS/hmmdefs -M hmmT parm/symbols

# some extra training at this level
hmmU/hmmdefs: htk-config hmmT/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmU
	HVite -C htk-config -H hmmT/macros -H hmmT/hmmdefs -S parm/train.scr \
              -i hmmU/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmU/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmT/macros -H hmmT/hmmdefs -M hmmU parm/symbols
hmmV/hmmdefs: htk-config hmmU/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmV
	HVite -C htk-config -H hmmU/macros -H hmmU/hmmdefs -S parm/train.scr \
              -i hmmV/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmV/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmU/macros -H hmmU/hmmdefs -M hmmV parm/symbols
hmmW/hmmdefs: htk-config hmmV/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmW
	HVite -C htk-config -H hmmV/macros -H hmmV/hmmdefs -S parm/train.scr \
              -i hmmW/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmW/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmV/macros -H hmmV/hmmdefs -M hmmW parm/symbols
hmmX/hmmdefs: htk-config hmmW/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmmX
	HVite -C htk-config -H hmmW/macros -H hmmW/hmmdefs -S parm/train.scr \
              -i hmmX/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmmX/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmW/macros -H hmmW/hmmdefs -M hmmX parm/symbols

# now make a tied mixture HMM
TIED_BEAM=-c 50
hmmY/hmmdefs: htk-config hmmX/hmmdefs parm/symbols tie.hed
	mkdir -p hmmY
	HERest -C htk-config -I hmmX/aligned.mlf -s hmmY/stats \
	  -S parm/train.scr -H hmmX/macros -H hmmX/hmmdefs -M hmmY parm/symbols
	echo "LS hmmY/stats" > hmmY/mix.hed
	cat tie.hed >> hmmY/mix.hed
	HHEd -C htk-config -H hmmX/macros -H hmmX/hmmdefs -M hmmY \
	  hmmY/mix.hed parm/symbols
# and train it!
hmmZ/hmmdefs: htk-config hmmY/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmZ
	HERest -C htk-config -I hmmX/aligned.mlf $(TIED_BEAM) \
	  -S parm/train.scr -H hmmY/macros -H hmmY/hmmdefs -M hmmZ parm/symbols
hmm10/hmmdefs: htk-config hmmZ/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm10
	HVite -C htk-config -H hmmZ/macros -H hmmZ/hmmdefs -S parm/train.scr \
              -i hmm10/aligned.mlf -m -o SWT -I parm/all2.mlf $(TIED_BEAM) \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm10/aligned.mlf $(TIED_BEAM) \
	  -S parm/train.scr -H hmmZ/macros -H hmmZ/hmmdefs -M hmm10 parm/symbols
hmm11/hmmdefs: htk-config hmm10/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm11
	HVite -C htk-config -H hmm10/macros -H hmm10/hmmdefs -S parm/train.scr \
              -i hmm11/aligned.mlf -m -o SWT -I parm/all2.mlf $(TIED_BEAM) \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm11/aligned.mlf $(TIED_BEAM) \
	  -S parm/train.scr -H hmm10/macros -H hmm10/hmmdefs -M hmm11 parm/symbols
hmm12/hmmdefs: htk-config hmm11/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm12
	HVite -C htk-config -H hmm11/macros -H hmm11/hmmdefs -S parm/train.scr \
              -i hmm12/aligned.mlf -m -o SWT -I parm/all2.mlf $(TIED_BEAM) \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -I hmm12/aligned.mlf $(TIED_BEAM) \
	  -S parm/train.scr -H hmm11/macros -H hmm11/hmmdefs -M hmm12 parm/symbols

# ta-da


%/recout.mlf: %/hmmdefs parm/train.scr parm/wdnet-single parm/dict parm/symbols
	HVite -C htk-config -H $*/macros -H $*/hmmdefs -S parm/train.scr -i $@ -t 250 150 1000 -w parm/wdnet-single parm/dict parm/symbols
%/recout-qual.mlf: %/hmmdefs parm/qual.scr parm/wdnet-single parm/dict parm/symbols
	HVite -C htk-config -H $*/macros -H $*/hmmdefs -S parm/qual.scr -i $@ -w parm/wdnet-single parm/dict parm/symbols
%/accuracy.txt: %/recout.mlf parm/all2.mlf parm/words
	HResults -p -I parm/all2.mlf parm/words $*/recout.mlf | \
	  tee $@ | head -7
%/accuracy-qual.txt: %/recout-qual.mlf parm/all2.mlf parm/words
	HResults -p -I parm/all2.mlf parm/words $*/recout-qual.mlf | \
	  tee $@ | head -7

very-clean: clean
	$(RM) -rf html parm
clean:
	$(RM) -rf hmm?

# prevent deletion of %/recout.mlf
.SECONDARY:
