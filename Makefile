UPPER_LETTERS=A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
LOWER_LETTERS=a b c d e f g h i j k l m n o p q r s t u v w x y z
DIGITS=0 1 2 3 4 5 6 7 8 9

parms: $(foreach l,$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS),parm/$(l).mlf)
html: $(foreach l,$(UPPER_LETTERS) $(LOWER_LETTERS) $(DIGITS),html/$(l).html)

html/%.html parm/%.mlf: json/%.json read.js
	@mkdir -p html parm/$*
	./read.js -H html/$*.html -M parm/$*.mlf -P parm/$* $<
