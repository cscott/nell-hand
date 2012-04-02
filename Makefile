UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

ALL_PARMS=$(foreach l,$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS),parm/$(l).mlf)
ALL_HTML=$(foreach l,$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS),html/$(l).html)

all: global

parms: $(ALL_PARMS)
html: $(ALL_HTML)

html/%.html parm/%.mlf: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -H html/$*.html -M parm/$*.mlf -P parm/$* $<

global: $(ALL_PARMS)
	mkdir -p hmm0
	HCompV -C htk-config -f 0.01 -m -M hmm0 proto parm/a/0000.htk parm/a/0001.htk
