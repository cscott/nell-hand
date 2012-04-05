UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

# set aside 20% of the training data for evaluation.
TRAINAMT=5
# total # of mixtures
MIX=9

#SYMBOLS=$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS)
SYMBOLS=$(UPPER_LETTERS)

ALL_SCRIPT=$(foreach l,$(SYMBOLS),parm/$(l).scr)
ALL_LABEL=$(foreach l,$(SYMBOLS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(SYMBOLS),html/$(l).html)

all: accuracy qual
accuracy: $(foreach n,9 Q R T U W X Z 10 12 13 15 16 18 19 1B 1C,hmm$(n)/accuracy.txt)
qual: $(foreach n,9 Q R T U W X Z 10 12 13 15 16 18 19 1B 1C,hmm$(n)/accuracy-qual.txt)

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr parm/%-qual.scr: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -T $(TRAINAMT) -H html/$*.html \
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
	for s in $(SYMBOLS); do \
	  echo $$s >> $@.tmp ; \
	done
	if cmp -s $@.tmp $@ ; then $(RM) $@.tmp ; else mv $@.tmp $@ ; fi
parm/dict: Makefile
	$(RM) -f $@.tmp
	touch $@.tmp
	for s in $(SYMBOLS); do \
	  echo $$s $$s >> $@.tmp ; \
	done
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
	for s in $(SYMBOLS); do \
	  echo '~h "'$$s'"' >> $@ ; \
	  sed -e '0,/^~h/d' < hmm0/proto >> $@ ; \
	done
hmm1/hmmdefs: htk-config hmm0/macros hmm0/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm1
	HERest -C htk-config -I parm/all.mlf \
	  -S parm/train.scr -H hmm0/macros -H hmm0/hmmdefs -M hmm1 parm/symbols
hmm2/hmmdefs: htk-config hmm1/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm2
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1/macros -H hmm1/hmmdefs -M hmm2 parm/symbols
hmm3/hmmdefs: htk-config hmm2/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm3
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm2/macros -H hmm2/hmmdefs -M hmm3 parm/symbols
hmm4/hmmdefs: htk-config hmm3/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm4
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm3/macros -H hmm3/hmmdefs -M hmm4 parm/symbols
hmm5/hmmdefs: htk-config hmm4/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm5
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm4/macros -H hmm4/hmmdefs -M hmm5 parm/symbols
hmm6/hmmdefs: htk-config hmm5/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm6
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm5/macros -H hmm5/hmmdefs -M hmm6 parm/symbols
hmm7/hmmdefs: htk-config hmm6/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm7
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm6/macros -H hmm6/hmmdefs -M hmm7 parm/symbols
hmm8/hmmdefs: htk-config hmm7/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm8
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm7/macros -H hmm7/hmmdefs -M hmm8 parm/symbols
hmm9/hmmdefs: htk-config hmm8/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm9
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm8/macros -H hmm8/hmmdefs -M hmm9 parm/symbols

# up to 2 mixtures
hmmP/hmmdefs: htk-config hmm9/hmmdefs parm/symbols
	mkdir -p hmmP
	HERest -C htk-config -I parm/all.mlf -s hmmP/stats \
	  -S parm/train.scr -H hmm9/macros -H hmm9/hmmdefs -M hmmP parm/symbols
	echo "LS hmmP/stats" > hmmP/mix.hed
	echo "PS 2 0.2" >> hmmP/mix.hed
	HHEd -C htk-config -H hmm9/macros -H hmm9/hmmdefs -M hmmP \
	  hmmP/mix.hed parm/symbols
hmmQ/hmmdefs: htk-config hmmP/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmQ
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmP/macros -H hmmP/hmmdefs -M hmmQ parm/symbols
hmmR/hmmdefs: htk-config hmmQ/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmR
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmQ/macros -H hmmQ/hmmdefs -M hmmR parm/symbols

# up to 4 mixtures
hmmS/hmmdefs: htk-config hmmR/hmmdefs parm/symbols
	mkdir -p hmmS
	HERest -C htk-config -I parm/all.mlf -s hmmS/stats \
	  -S parm/train.scr -H hmmR/macros -H hmmR/hmmdefs -M hmmS parm/symbols
	echo "LS hmmS/stats" > hmmS/mix.hed
	echo "PS 4 0.2" >> hmmS/mix.hed
	HHEd -C htk-config -H hmmR/macros -H hmmR/hmmdefs -M hmmS \
	  hmmS/mix.hed parm/symbols
hmmT/hmmdefs: htk-config hmmS/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmT
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmS/macros -H hmmS/hmmdefs -M hmmT parm/symbols
hmmU/hmmdefs: htk-config hmmT/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmU
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmT/macros -H hmmT/hmmdefs -M hmmU parm/symbols

# up to 6 mixtures
hmmV/hmmdefs: htk-config hmmU/hmmdefs parm/symbols
	mkdir -p hmmV
	HERest -C htk-config -I parm/all.mlf -s hmmV/stats \
	  -S parm/train.scr -H hmmU/macros -H hmmU/hmmdefs -M hmmV parm/symbols
	echo "LS hmmV/stats" > hmmV/mix.hed
	echo "PS 6 0.2" >> hmmV/mix.hed
	HHEd -C htk-config -H hmmU/macros -H hmmU/hmmdefs -M hmmV \
	  hmmV/mix.hed parm/symbols
hmmW/hmmdefs: htk-config hmmV/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmW
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmV/macros -H hmmV/hmmdefs -M hmmW parm/symbols
hmmX/hmmdefs: htk-config hmmW/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmX
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmW/macros -H hmmW/hmmdefs -M hmmX parm/symbols

# up to 8 mixtures
hmmY/hmmdefs: htk-config hmmX/hmmdefs parm/symbols
	mkdir -p hmmY
	HERest -C htk-config -I parm/all.mlf -s hmmY/stats \
	  -S parm/train.scr -H hmmX/macros -H hmmX/hmmdefs -M hmmY parm/symbols
	echo "LS hmmY/stats" > hmmY/mix.hed
	echo "PS 8 0.2" >> hmmY/mix.hed
	HHEd -C htk-config -H hmmX/macros -H hmmX/hmmdefs -M hmmY \
	  hmmY/mix.hed parm/symbols
hmmZ/hmmdefs: htk-config hmmY/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmZ
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmY/macros -H hmmY/hmmdefs -M hmmZ parm/symbols
hmm10/hmmdefs: htk-config hmmZ/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm10
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmZ/macros -H hmmZ/hmmdefs -M hmm10 parm/symbols

# up to 9 mixtures
hmm11/hmmdefs: htk-config hmm10/hmmdefs parm/symbols
	mkdir -p hmm11
	HERest -C htk-config -I parm/all.mlf -s hmm11/stats \
	  -S parm/train.scr -H hmm10/macros -H hmm10/hmmdefs -M hmm11 parm/symbols
	echo "LS hmm11/stats" > hmm11/mix.hed
	echo "PS 9 0.2" >> hmm11/mix.hed
	HHEd -C htk-config -H hmm10/macros -H hmm10/hmmdefs -M hmm11 \
	  hmm11/mix.hed parm/symbols
hmm12/hmmdefs: htk-config hmm11/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm12
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm11/macros -H hmm11/hmmdefs -M hmm12 parm/symbols
hmm13/hmmdefs: htk-config hmm12/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm13
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm12/macros -H hmm12/hmmdefs -M hmm13 parm/symbols

# up to 10 mixtures
hmm14/hmmdefs: htk-config hmm13/hmmdefs parm/symbols
	mkdir -p hmm14
	HERest -C htk-config -I parm/all.mlf -s hmm14/stats \
	  -S parm/train.scr -H hmm13/macros -H hmm13/hmmdefs -M hmm14 parm/symbols
	echo "LS hmm14/stats" > hmm14/mix.hed
	echo "PS 10 0.2" >> hmm14/mix.hed
	HHEd -C htk-config -H hmm13/macros -H hmm13/hmmdefs -M hmm14 \
	  hmm14/mix.hed parm/symbols
hmm15/hmmdefs: htk-config hmm14/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm15
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm14/macros -H hmm14/hmmdefs -M hmm15 parm/symbols
hmm16/hmmdefs: htk-config hmm15/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm16
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm15/macros -H hmm15/hmmdefs -M hmm16 parm/symbols

# up to 12 mixtures
hmm17/hmmdefs: htk-config hmm16/hmmdefs parm/symbols
	mkdir -p hmm17
	HERest -C htk-config -I parm/all.mlf -s hmm17/stats \
	  -S parm/train.scr -H hmm16/macros -H hmm16/hmmdefs -M hmm17 parm/symbols
	echo "LS hmm17/stats" > hmm17/mix.hed
	echo "PS 12 0.2" >> hmm17/mix.hed
	HHEd -C htk-config -H hmm16/macros -H hmm16/hmmdefs -M hmm17 \
	  hmm17/mix.hed parm/symbols
hmm18/hmmdefs: htk-config hmm17/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm18
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm17/macros -H hmm17/hmmdefs -M hmm18 parm/symbols
hmm19/hmmdefs: htk-config hmm18/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm19
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm18/macros -H hmm18/hmmdefs -M hmm19 parm/symbols

# up to 14 mixtures
hmm1A/hmmdefs: htk-config hmm19/hmmdefs parm/symbols
	mkdir -p hmm1A
	HERest -C htk-config -I parm/all.mlf -s hmm1A/stats \
	  -S parm/train.scr -H hmm19/macros -H hmm19/hmmdefs -M hmm1A parm/symbols
	echo "LS hmm1A/stats" > hmm1A/mix.hed
	echo "PS 14 0.2" >> hmm1A/mix.hed
	HHEd -C htk-config -H hmm19/macros -H hmm19/hmmdefs -M hmm1A \
	  hmm1A/mix.hed parm/symbols
hmm1B/hmmdefs: htk-config hmm1A/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm1B
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1A/macros -H hmm1A/hmmdefs -M hmm1B parm/symbols
hmm1C/hmmdefs: htk-config hmm1B/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm1C
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1B/macros -H hmm1B/hmmdefs -M hmm1C parm/symbols



%/recout.mlf: %/hmmdefs parm/train.scr parm/wdnet-single parm/dict parm/symbols
	HVite -C htk-config -H $*/macros -H $*/hmmdefs -S parm/train.scr -i $@ -w parm/wdnet-single parm/dict parm/symbols
%/recout-qual.mlf: %/hmmdefs parm/qual.scr parm/wdnet-single parm/dict parm/symbols
	HVite -C htk-config -H $*/macros -H $*/hmmdefs -S parm/qual.scr -i $@ -w parm/wdnet-single parm/dict parm/symbols
%/accuracy.txt: %/recout.mlf parm/all.mlf parm/symbols
	HResults -p -I parm/all.mlf parm/symbols $*/recout.mlf | \
	  tee $@ | head -7
%/accuracy-qual.txt: %/recout-qual.mlf parm/all.mlf parm/symbols
	HResults -p -I parm/all.mlf parm/symbols $*/recout-qual.mlf | \
	  tee $@ | head -7

very-clean: clean
	$(RM) -rf html parm
clean:
	$(RM) -rf hmm?

# prevent deletion of %/recout.mlf
.SECONDARY:
