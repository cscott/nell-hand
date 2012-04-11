define(['ometa', 'q', 'text!hmmgram.ometa'], function(ometa, Q, hmmgram) {
    var deferred = Q.defer();

    ometa.createParser(hmmgram, function(error, success) {
        if (error) {
            console.error("Couldn't parse HMM grammar.", error.inner);
            deferred.reject(error.inner);
        } else {
            // tweak success.parse so it also returns a promise.
            var parse = success.parse;
            deferred.resolve(function (input, rule) {
                var deferred2 = Q.defer();
                try { // workaround poor error handling in ometajs callback
                    parse(input, rule, function(error, success) {
                        if (error) {
                            console.error("Couldn't parse.", error.inner);
                            deferred2.reject(error);
                        } else {
                            deferred2.resolve(success);
                        }
                    });
                } catch (ex) {
                    console.error("Couldn't parse.", ex.errorPos);
                    deferred2.reject(ex);
                }
                return deferred2.promise;
            });
        }
    });

    return deferred.promise;
});
