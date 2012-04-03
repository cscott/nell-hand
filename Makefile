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

all: hmm3/hmmdefs

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf parm/%.scr: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -T $(TRAINAMT) -H html/$*.html \
		-M parm/$*.mlf -P parm/$* -S parm/$*.scr \
		$<

parm/train.scr: $(ALL_SCRIPT)
	cat $(ALL_SCRIPT) > $@

parm/all.mlf: $(ALL_LABEL)
	echo "#!MLF!#" > $@
	cat $^ | grep -v -F '#!MLF!#' >> $@

# global mean/variance computation
hmm0/proto hmm0/vFloors: htk-config proto parm/train.scr
	mkdir -p hmm0
	HCompV -C htk-config -f 0.01 -m -S parm/train.scr -M hmm0 proto

# create flat-start monophone models
hmm0/macros: hmm0/vFloors
	echo "~o <VecSize> 27 <USER_D_A>" > $@
	cat $< >> $@
hmm0/hmmdefs hmm0/symbols: hmm0/proto
	$(RM) -f hmm0/hmmdefs hmm0/symbols
	touch hmm0/hmmdefs hmm0/symbols
	for s in $(SYMBOLS); do \
	  echo $$s >> hmm0/symbols ; \
	  echo '~h "'$$s'"' >> hmm0/hmmdefs ; \
	  sed -e '0,/^~h/d' < hmm0/proto >> hmm0/hmmdefs ; \
	done
hmm1/hmmdefs: htk-config hmm0/macros hmm0/hmmdefs hmm0/symbols parm/all.mlf
	mkdir -p hmm1
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm0/macros -H hmm0/hmmdefs -M hmm1 hmm0/symbols
hmm2/hmmdefs: htk-config hmm1/macros hmm1/hmmdefs hmm0/symbols parm/all.mlf
	mkdir -p hmm2
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm1/macros -H hmm1/hmmdefs -M hmm2 hmm0/symbols
hmm3/hmmdefs: htk-config hmm2/macros hmm2/hmmdefs hmm0/symbols parm/all.mlf
	mkdir -p hmm3
	HERest -C htk-config -I parm/all.mlf -t 250 150 1000 \
	  -S parm/train.scr -H hmm2/macros -H hmm2/hmmdefs -M hmm3 hmm0/symbols

clean:
	$(RM) -rf html parm hmm0 hmm1 hmm2 hmm3
