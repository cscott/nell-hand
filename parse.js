define(['ometa', 'q', 'text!hmmgram.ometa'], function(ometa, Q, hmmgram) {
    var deferred = Q.defer();

    console.log(hmmgram);
    ometa.createParser(hmmgram, function(error, success) {
        if (error) {
            console.error("Couldn't parse HMM grammar.");
            deferred.reject(error.inner);
        } else {
            // tweak success.parse so it also returns a promise.
            var deferred2 = Q.defer();
            var parse = success.parse;
            deferred.resolve(function (input, rule) {
                parse(input, rule, function(error, success) {
                    if (error) {
                        deferred2.reject(error);
                    } else {
                        deferred2.resolve(success);
                    }
                });
                return deferred2.promise;
            });
        }
    });

    return deferred.promise;
});
