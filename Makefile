UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

# set aside 20% of the training data for evaluation.
TRAINAMT=5

#SYMBOLS=$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS)
SYMBOLS=$(UPPER_LETTERS)

ALL_SCRIPT=$(foreach l,$(SYMBOLS),parm/$(l).scr)
ALL_LABEL=$(foreach l,$(SYMBOLS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(SYMBOLS),html/$(l).html)

# accuracy peaks for hmm8 at 83.58%
# hmmE uses 3 mixtures and 12 states, gets accuracy up to 87.17%
# with 3 mix, 12 states, penUp feature and no deltas, hmmE gets up to 86.48%
# with 5 mix,  " "     , "      "      "   "   "    , hmmH gets up to 87.84%
# adding deltas and acceleration to the above, hmmJ reaches 90.07%
# average 9 mixtures,  6 states, penup, delta, accel: hmmN reaches 88.69%
# average 9 mixtures,  8 states, penup, delta, accel: hmmN reaches 90.56%
# average 9 mixtures, 10 states, penup, delta, accel: hmmN reaches 91.84%
# average 9 mixtures, 12 states, penup, delta, accel: hmmN reaches 92.57%
# average 9 mixtures, 14 states, penup, delta, accel: hmmN reaches 93.41%
# average 9 mixtures, 16 states, penup, delta, accel: hmmN reaches 94.17%[85.77]
# average 12 mixtures,16 states, penup, delta, accel: hmmN reaches 94.50%[85.77]
# average 12 mixtures,16 states, penup, delta, accel: hmmO reaches 94.59%[85.77]
# avg 9 mix, 5x2  structure: 88.69% (10 states, like 4 states paralleled)[76.08]
# avg 9 mix, 5x2x structure: 90.99%                                      [76.60]
# avg 9 mix, 6x2  structure: 90.24% (12 states, like 6 states paralleled)[78.81]
# avg 9 mix, 6x2x structure: 92.16%                                      [77.48]
# avg 9 mix, 7x2  structure: 90.56% (14 states, like 8 states paralleled)[81.30]
# avg 9 mix, 7x2x structure: 93.17%                                      [81.65]
all: $(foreach n,1 2 3 4 5 6 7 8 9 B D F H J K L M N O,hmm$(n)/accuracy.txt) \
	hmmO/accuracy-qual.txt

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
# scale up to 12 mixtures... slowly
hmmA/hmmdefs: htk-config hmm9/hmmdefs parm/symbols
	mkdir -p hmmA
	HERest -C htk-config -I parm/all.mlf -s hmmA/stats \
	  -S parm/train.scr -H hmm9/macros -H hmm9/hmmdefs -M hmmA parm/symbols
	echo "LS hmmA/stats" > hmmA/mix.hed
	echo "PS 12 0.2 5" >> hmmA/mix.hed
	HHEd -C htk-config -H hmm9/macros -H hmm9/hmmdefs -M hmmA \
	  hmmA/mix.hed parm/symbols
hmmB/hmmdefs: htk-config hmmA/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmB
	HERest -C htk-config -I parm/all.mlf \
	  -S parm/train.scr -H hmmA/macros -H hmmA/hmmdefs -M hmmB parm/symbols

hmmC/hmmdefs: htk-config hmmB/hmmdefs parm/symbols
	mkdir -p hmmC
	HERest -C htk-config -I parm/all.mlf -s hmmC/stats \
	  -S parm/train.scr -H hmmB/macros -H hmmB/hmmdefs -M hmmC parm/symbols
	echo "LS hmmC/stats" > hmmC/mix.hed
	echo "PS 12 0.2 4" >> hmmC/mix.hed
	HHEd -C htk-config -H hmmB/macros -H hmmB/hmmdefs -M hmmC \
	  hmmC/mix.hed parm/symbols
hmmD/hmmdefs: htk-config hmmC/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmD
	HERest -C htk-config -I parm/all.mlf \
	  -S parm/train.scr -H hmmC/macros -H hmmC/hmmdefs -M hmmD parm/symbols

hmmE/hmmdefs: htk-config hmmD/hmmdefs parm/symbols
	mkdir -p hmmE
	HERest -C htk-config -I parm/all.mlf -s hmmE/stats \
	  -S parm/train.scr -H hmmD/macros -H hmmD/hmmdefs -M hmmE parm/symbols
	echo "LS hmmE/stats" > hmmE/mix.hed
	echo "PS 12 0.2 3" >> hmmE/mix.hed
	HHEd -C htk-config -H hmmD/macros -H hmmD/hmmdefs -M hmmE \
	  hmmE/mix.hed parm/symbols
hmmF/hmmdefs: htk-config hmmE/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmF
	HERest -C htk-config -I parm/all.mlf \
	  -S parm/train.scr -H hmmE/macros -H hmmE/hmmdefs -M hmmF parm/symbols

hmmG/hmmdefs: htk-config hmmF/hmmdefs parm/symbols
	mkdir -p hmmG
	HERest -C htk-config -I parm/all.mlf -s hmmG/stats \
	  -S parm/train.scr -H hmmF/macros -H hmmF/hmmdefs -M hmmG parm/symbols
	echo "LS hmmG/stats" > hmmG/mix.hed
	echo "PS 12 0.2 2" >> hmmG/mix.hed
	HHEd -C htk-config -H hmmF/macros -H hmmF/hmmdefs -M hmmG \
	  hmmG/mix.hed parm/symbols
hmmH/hmmdefs: htk-config hmmG/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmH
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmG/macros -H hmmG/hmmdefs -M hmmH parm/symbols

hmmI/hmmdefs: htk-config hmmH/hmmdefs parm/symbols
	mkdir -p hmmI
	HERest -C htk-config -I parm/all.mlf -s hmmI/stats \
	  -S parm/train.scr -H hmmH/macros -H hmmH/hmmdefs -M hmmI parm/symbols
	echo "LS hmmI/stats" > hmmI/mix.hed
	echo "PS 12 0.2 1" >> hmmI/mix.hed
	HHEd -C htk-config -H hmmH/macros -H hmmH/hmmdefs -M hmmI \
	  hmmI/mix.hed parm/symbols
hmmJ/hmmdefs: htk-config hmmI/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmJ
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmI/macros -H hmmI/hmmdefs -M hmmJ parm/symbols

hmmK/hmmdefs: htk-config hmmJ/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmK
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmJ/macros -H hmmJ/hmmdefs -M hmmK parm/symbols
hmmL/hmmdefs: htk-config hmmK/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmL
	HERest -C htk-config -I parm/all.mlf \
	  -S parm/train.scr -H hmmK/macros -H hmmK/hmmdefs -M hmmL parm/symbols
hmmM/hmmdefs: htk-config hmmL/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmM
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmL/macros -H hmmL/hmmdefs -M hmmM parm/symbols
hmmN/hmmdefs: htk-config hmmM/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmN
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmM/macros -H hmmM/hmmdefs -M hmmN parm/symbols
hmmO/hmmdefs: htk-config hmmN/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmmO
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmmN/macros -H hmmN/hmmdefs -M hmmO parm/symbols



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
