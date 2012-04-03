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

# accuracy peaks for hmm2 at 67.81% =(
all: hmm1/accuracy.txt hmm2/accuracy.txt hmm3/accuracy.txt hmm4/accuracy.txt

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -T $(TRAINAMT) -H html/$*.html \
		-M parm/$*.mlf -P parm/$* -S parm/$*.scr \
		$<

# helper: dump parameter file
parm/%.out: parm/%.htk
	HList -C htk-config -t $<

parm/train.scr: $(ALL_SCRIPT)
	cat $(ALL_SCRIPT) > $@

parm/all.mlf: $(ALL_LABEL)
	echo "#!MLF!#" > $@
	cat $^ | grep -v -F '#!MLF!#' >> $@

parm/gram-single: Makefile
	echo "( $(firstword $(SYMBOLS)) $(patsubst %,|%,$(wordlist 2,$(words $(SYMBOLS)),$(SYMBOLS))) )" > $@
parm/gram-multi: Makefile
	echo "( < $(firstword $(SYMBOLS)) $(patsubst %,|%,$(wordlist 2,$(words $(SYMBOLS)),$(SYMBOLS))) > )" > $@
parm/wdnet%: parm/gram%
	HParse $< $@
parm/symbols: #Makefile
	$(RM) -f $@
	touch $@
	for s in $(SYMBOLS); do \
	  echo $$s >> $@ ; \
	done
parm/dict: Makefile
	$(RM) -f $@
	touch $@
	for s in $(SYMBOLS); do \
	  echo $$s $$s >> $@ ; \
	done

# test word network
gen-%: parm/wdnet% hmm0/symbols
	HSGen $< hmm0/symbols

# global mean/variance computation
hmm0/proto hmm0/vFloors: htk-config proto parm/train.scr
	mkdir -p hmm0
	HCompV -C htk-config -f 0.01 -m -S parm/train.scr -M hmm0 proto

# create flat-start monophone models
hmm0/macros: hmm0/vFloors
	echo "~o <VecSize> 27 <USER_D_A>" > $@
	cat $< >> $@
hmm0/hmmdefs: hmm0/proto
	$(RM) -f $@
	touch $@
	for s in $(SYMBOLS); do \
	  echo '~h "'$$s'"' >> $@ ; \
	  sed -e '0,/^~h/d' < hmm0/proto >> $@ ; \
	done
hmm1/hmmdefs: htk-config hmm0/macros hmm0/hmmdefs parm/symbols parm/all.mlf
	mkdir -p hmm1
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
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

%/recout.mlf: %/hmmdefs parm/train.scr parm/wdnet-single parm/dict parm/symbols
	HVite -C htk-config -H $*/macros -H $*/hmmdefs -S parm/train.scr -i $@ -w parm/wdnet-single parm/dict parm/symbols
%/accuracy.txt: %/recout.mlf parm/all.mlf parm/symbols
	HResults -I parm/all.mlf parm/symbols $*/recout.mlf | tee $@

clean:
	$(RM) -rf html parm hmm0 hmm1 hmm2 hmm3 hmm4
