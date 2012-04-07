UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

# set aside 20% of the training data for evaluation.
TRAINAMT=5
# total # of mixtures
MIX=9
# total # of allographs to train
ALLOGRAPHS=4
# number of streams (used for vector quantization)
NSTREAMS=3

#SYMBOLS=$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS)
SYMBOLS=$(UPPER_LETTERS)

ALL_SCRIPT=$(foreach l,$(SYMBOLS),parm/$(l).scr)
ALL_LABEL=$(foreach l,$(SYMBOLS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(SYMBOLS),html/$(l).html)

all: hmm9/accuracy.txt hmm9/accuracy-qual.txt
accuracy: $(foreach n,1 2 3 4 5 6 7 8 9,hmm$(n)/accuracy.txt)
qual: $(foreach n,1 2 3 4 5 6 7 8 9,hmm$(n)/accuracy-qual.txt)

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr parm/%-qual.scr: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -T $(TRAINAMT) -H html/$*.html -A $(ALLOGRAPHS) \
		-M parm/$*.mlf -P parm/$* -S parm/$*.scr -Q parm/$*-qual.scr \
		$<

# helper: dump parameter file
parm/%.out: parm/%.htk
	HList -C htk-config -n $(NSTREAMS) -t $< | tee $@
# vector quantization whoo
parm/%.vq: parm/%.htk
	HCopy -C htk-config $< $@

parm/train.scr: $(ALL_SCRIPT)
	cat $(ALL_SCRIPT) > $@
# cut down version of parm/train.scr with only those signals longer than 18
# frames long.  This is needed to bootstrap because HInit can't deal with
# short signals and skip states. (HERest does just fine of course.)
parm/train-18.scr: parm/train.scr
	( for f in $$(cat $< ) ; do if [ $$(stat --format=%s $$f) -gt 692 ] ; then echo $$f ; fi; done ) > $@
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

# vector quantization
STREAM_SIZES=-n 1 256 -n 2 64 -n 3 16
# -e is euclidean distance, -d is diagonal covariance, -f is full covariance
#  linear, 3 streams, 256 / 64 / 16 entries
# (linvq-f is slowest!)
linvq-e: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr $@
linvq-d: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr -d $@
# results in: "CovInvert: [0.001403 ...] not invertible"
linvq-f: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr -f $@
#  tree, 3 streams, 256 / 64 / 16 entries
# (treevq-e is fastest!)
treevq-e: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr -t $@
treevq-d: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr -t -d $@
# results in: "CovInvert: [0.071793 ...] not invertible"
treevq-f: htk-config parm/train.scr
	HQuant -C htk-config -C novq-config -s $(NSTREAMS) \
	       $(STREAM_SIZES) -S parm/train.scr -t -f $@

# select which codebook to use!
codebook: treevq-e
	if cmp -s $< $@ ; then echo $@ up to date. ; else cp $< $@ ; fi

# global mean/variance computation
hmm0/proto: htk-config proto parm/train-18.scr codebook
	mkdir -p hmm0
	HInit -C htk-config -T 1 -w 1.0 -S parm/train-18.scr -M hmm0 proto

# create flat-start monophone models
hmm0/macros: proto
	mkdir -p hmm0
	head -1 $< > $@
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
	HERest -C htk-config -w 1 -I parm/allograph.mlf \
	  -S parm/train.scr -H hmm0/macros -H hmm0/hmmdefs -M hmm1 parm/symbols
hmm2/hmmdefs: htk-config hmm1/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm2
	HVite -C htk-config -H hmm1/macros -H hmm1/hmmdefs -S parm/train.scr \
              -i hmm2/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm2/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1/macros -H hmm1/hmmdefs -M hmm2 parm/symbols
hmm3/hmmdefs: htk-config hmm2/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm3
	HVite -C htk-config -H hmm2/macros -H hmm2/hmmdefs -S parm/train.scr \
              -i hmm3/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm3/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm2/macros -H hmm2/hmmdefs -M hmm3 parm/symbols
hmm4/hmmdefs: htk-config hmm3/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm4
	HVite -C htk-config -H hmm3/macros -H hmm3/hmmdefs -S parm/train.scr \
              -i hmm4/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm4/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm3/macros -H hmm3/hmmdefs -M hmm4 parm/symbols
hmm5/hmmdefs: htk-config hmm4/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm5
	HVite -C htk-config -H hmm4/macros -H hmm4/hmmdefs -S parm/train.scr \
              -i hmm5/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm5/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm4/macros -H hmm4/hmmdefs -M hmm5 parm/symbols
hmm6/hmmdefs: htk-config hmm5/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm6
	HVite -C htk-config -H hmm5/macros -H hmm5/hmmdefs -S parm/train.scr \
              -i hmm6/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm6/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm5/macros -H hmm5/hmmdefs -M hmm6 parm/symbols
hmm7/hmmdefs: htk-config hmm6/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm7
	HVite -C htk-config -H hmm6/macros -H hmm6/hmmdefs -S parm/train.scr \
              -i hmm7/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm7/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm6/macros -H hmm6/hmmdefs -M hmm7 parm/symbols
hmm8/hmmdefs: htk-config hmm7/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm8
	HVite -C htk-config -H hmm7/macros -H hmm7/hmmdefs -S parm/train.scr \
              -i hmm8/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm8/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm7/macros -H hmm7/hmmdefs -M hmm8 parm/symbols
hmm9/hmmdefs: htk-config hmm8/hmmdefs parm/dict parm/symbols parm/all2.mlf
	mkdir -p hmm9
	HVite -C htk-config -H hmm8/macros -H hmm8/hmmdefs -S parm/train.scr \
              -i hmm9/aligned.mlf -m -o SWT -I parm/all2.mlf \
              -y lab parm/dict parm/symbols
	HERest -C htk-config -w 1 -I hmm9/aligned.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm8/macros -H hmm8/hmmdefs -M hmm9 parm/symbols
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
	$(RM) -rf html parm codebook
clean:
	$(RM) -rf hmm?

# prevent deletion of %/recout.mlf
.SECONDARY:
