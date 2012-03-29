#!/bin/bash
mkdir -p html
for l in \
    a b c d e f g h i j k l m n o p q r s t u v w x y z \
    A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
    0 1 2 3 4 5 6 7 8 9 ; do
    echo $l
    mkdir -p parm/$l
    ./read.js -H html/${l}.html -d parm/$l ../uptools3/json/${l}.json
done
