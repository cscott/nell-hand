UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

# set aside 20% of the training data for evaluation.
TRAINAMT=5
# HMM type: discrete, mix, tiedmix
HMMTYPE=discrete
# HMM topology
NSTATES=16
TOPOLOGY=
# total # of mixtures (for mix, tiedmix types)
MIX=5
# total # of allographs to train
ALLOGRAPHS=4
# number of streams
# (used for discrete and tiedmix HMMs)
NSTREAMS=3
STREAM1_SIZE=256
STREAM2_SIZE=128
STREAM3_SIZE=128
# override final step here if final is overtrained
#JSONSTEP=$(FINALSTEP)
JSONSTEP=9

#SYMBOLS=$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS)
SYMBOLS=$(UPPER_LETTERS)

ALL_SCRIPT=$(foreach l,$(SYMBOLS),parm/$(l).scr)
ALL_LABEL=$(foreach l,$(SYMBOLS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(SYMBOLS),html/$(l).html)

all: accuracy qual json

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr parm/%-qual.scr: json/%.json unipen2htk.js
	@mkdir -p html parm/$*
	./unipen2htk.js -T $(TRAINAMT) -H html/$*.html -A $(ALLOGRAPHS) \
		-M parm/$*.mlf -P parm/$* -S parm/$*.scr -Q parm/$*-qual.scr \
		$<

# helper: dump parameter file
parm/%.out: parm/%.htk htk-config $(if $(filter discrete,$(HMMTYPE)),codebook)
	HList -C htk-config -n $(NSTREAMS) -t $< | tee $@
all-out: $(patsubst %.htk,%.out,$(wildcard parm/*/*.htk))

parmVQ:
	$(MAKE) codebook
	./hmm2json.js -o codebook.json -c codebook
	for l in $(SYMBOLS); do \
	  mkdir -p parmVQ/$$l ; \
	  ./unipen2htk.js -d -c codebook.json -T $(TRAINAMT) -A $(ALLOGRAPHS) -P parmVQ/$$l json/$$l.json ; \
	done

# vector quantization whoo
parm/%.vq: parm/%.htk htk-config $(if $(filter discrete,$(HMMTYPE)),codebook)
	HCopy -C htk-config $< $@
all-vq: $(patsubst %.htk,%.vq,$(wildcard parm/*/*.htk))

parm/train.scr: $(ALL_SCRIPT)
	cat $(ALL_SCRIPT) > $@
# cut down version of parm/train.scr with only those signals longer than 18
# frames long.  This is needed to bootstrap because HInit can't deal with
# short signals and skip states. (HERest does just fine of course.)
parm/train-18.scr: parm/train.scr
	( for f in $$(cat $< ) ; do \
	    if [ $$(stat --format=%s $$f) -gt 692 ] ; then echo $$f ; fi; \
	done ) > $@
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

include Makefile.$(HMMTYPE)

accuracy: $(foreach n,$(ALLSTEPS),hmm$(n)/accuracy.txt)
qual:     $(foreach n,$(ALLSTEPS),hmm$(n)/accuracy-qual.txt)
final-accuracy: hmm$(FINALSTEP)/accuracy.txt hmm$(FINALSTEP)/accuracy-qual.txt
json:     $(JSONOUT)
	echo $(JSONOUT) up to date.

# ta-da
$(JSONOUT): hmm$(JSONSTEP)/hmmdefs
	./hmm2json.js -o $@ $(if $(filter discrete,$(HMMTYPE)),-c codebook) \
	              hmm$(JSONSTEP)/macros hmm$(JSONSTEP)/hmmdefs

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

# evaluate javascript implementation of recognizer
js-recout.mlf: $(JSONOUT) parm/train.scr
	./recog.js -A -o $@ -S parm/train.scr $(JSONOUT)
js-recout-qual.mlf: $(JSONOUT) parm/qual.scr
	./recog.js -A -o $@ -S parm/qual.scr $(JSONOUT)
js-accuracy.txt: js-recout.mlf parm/all2.mlf parm/words
	HResults -p -I parm/all2.mlf parm/words js-recout.mlf | \
	  tee $@ | head -7
js-accuracy-qual.txt: js-recout-qual.mlf parm/all2.mlf parm/words
	HResults -p -I parm/all2.mlf parm/words js-recout-qual.mlf | \
	  tee $@ | head -7

very-clean: clean
	$(RM) -rf html parm codebook htk-config $(JSONOUT)
clean:
	$(RM) -rf hmm? hmm?? proto \
	  js-accuracy.txt js-accuracy-qual.txt js-recout.mlf js-recout-qual.mlf

# prevent deletion of %/recout.mlf
.SECONDARY:
