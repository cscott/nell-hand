if (typeof define !== 'function') {
    var define = require('amdefine')(module);
}
define(['./features'], function(Features) {
    var tolog = function(x) {
        return -Math.log(x)*2371.8;
    };
    var fromlog = function(x) {
        return Math.exp(-x/2371.8);
    };

    var Token = function(model, state) {
        this.model = model;
        this.state = state;
    };

    var omerge = function() {
        var r = arguments.length ? arguments[0] : {}, o;
        for (var i=1; i<arguments.length; i++) {
            o = arguments[i];
            for (name in o) {
                if (o.hasOwnProperty(name)) {
                    r[name] = o[name];
                }
            }
        }
        return r;
    };

    var extract_models = function(hmmdef, mkmodel, process_codebook) {
        var globals = {};
        var models = [];

        for (var i=0; i<hmmdef.length; i++) {
            switch(hmmdef[i].type) {
            case '<comment>':
                /* ignore */
                break;
            case '<codebook>':
                process_codebook(hmmdef[i].value);
                break;
            case '~o':
                globals = omerge(globals, hmmdef[i].value);
                break;
            case '~h':
                models.push(mkmodel(hmmdef[i].name, globals, hmmdef[i].value));
                break;
            default:
                // ignore other definitions for now.
                // XXX in the future we might want to expand macro references
                break;
            }
        }
        return models;
    };

    var make_discrete_recog = function(hmmdef) {
        var vq_features;
        var process_codebook = function(codebook) {
            vq_features = Features.make_vq(codebook);
        };
        var expand_weightlist = function(a) {
            var r = [];
            for (var i=0; i<a.length; i++) {
                for (var j=0; j<a[i][1]; j++) {
                    r.push(a[i][0]);
                }
            }
            return r;
        };
        var mkmodel = function(name, globals, def) {
            var states = [], i, j;
            // process output probabilities
            states.push({ id: 0, start: true, pred: [] }); /* entry state */
            for (i=2; i < def.NumStates; i++) {
                states.push({
                    id: states.length,
                    output: def.States[i].Streams.map(function(d) {
                        return expand_weightlist(d.DProb).map(function(x) {
                            // convert from oddly-scaled DProb values into
                            // standard log probability.
                            return x/-2371.8;
                        });
                    }),
                    // XXX we ignore stream weights
                    weights: def.States[i].SWeights,
                    pred: []
                });
                def.States[i].NumMixes.forEach(function(len, j) {
                    console.assert(states[i-1].output[j].length===len);
                });
            }
            states.push({ id: states.length, pred: [] }); /* exit state */
            // process transition matrix
            console.assert(def.TransP.type==='square');
            console.assert(def.TransP.rows===def.NumStates);
            for (i=0; i < def.NumStates-1; i++) { /* from state */
                for (j=0; j < def.NumStates; j++) { /* to state */
                    var aij = def.TransP.entries[(i*def.NumStates)+j];
                    if (aij > 0)
                        states[j].pred.push([states[i], Math.log(aij)]);
                }
            }
            states.forEach(function(s, i) {
                if (i>0 && s.pred.length==0)
                    console.warn("No transitions into state", i, "in", name);
            });
            return { name: name, states: states };
        };
        var models = extract_models(hmmdef, mkmodel, process_codebook);
        console.assert(models.length);

        var make_maxp = function(input) {
            var phi = function(phi, state, t) {
                var j;
                if (state.start) {
                    return (t===0) ? 0 : -Infinity; /* base case */
                }
                if (t===0) return -Infinity;
                if (state.pred.length===0) return -Infinity; /* unusual */

                // compute probability of emitting signal o_t in this state
                var o_t = input[t-1];
                var b_j = 0;
                for (j = 0; j<o_t.length; j++) {
                    /* XXX ignoring stream weights here */
                    b_j += state.output[j][o_t[j]];
                }

                // maximized prob of reaching this state
                console.assert(state.pred.length);
                var bestp = phi(phi, state.pred[0][0], t-1) + state.pred[0][1];
                for (j = 1; j < state.pred.length; j++) {
                    var p = phi(phi, state.pred[j][0], t-1) + state.pred[j][1];
                    if (p > bestp) { bestp = p; }
                }
                return bestp + b_j;
            };
            var phiN = function(phi, pred_state, aiN) {
                /*
                console.log('-- phi_N('+input.length+')',
                            phi(phi, pred_state, input.length),
                            '+', aiN);
                */
                return phi(phi, pred_state, input.length) + aiN;
            };
            var maxp = function(model) {
                //console.log("Considering "+model.name);

                // need to memoize the computation of phi
                var memo_table = model.states.map(function(){ return [] });
                var memoized_phi = function(_, state, t) {
                    if (!(t in memo_table[state.id])) {
                        memo_table[state.id][t] = phi(memoized_phi, state, t);
                        /*
                        console.log('phi_'+state.id+'('+t+')',
                                    memo_table[state.id][t]);
                        */
                    }
                    return memo_table[state.id][t];
                };

                var pred = model.states[model.states.length-1].pred;
                console.assert(pred.length > 0);

                var bestp = phiN(memoized_phi, pred[0][0], pred[0][1]);
                for (var j=1; j<pred.length; j++) {
                    var p = phiN(memoized_phi, pred[j][0], pred[j][1]);
                    if (p > bestp) bestp = p;
                }
                return bestp;
            };
            return maxp;
        };

        return function(data_set) {
            vq_features(data_set);
            if (false) return ["A1", 0]; // DEBUGGING: time VQ in isolation

            var maxp = make_maxp(data_set.vq);

            var best=0, bestp = maxp(models[0]), p;
            for (var i=1; i<models.length; i++) {
                p = maxp(models[i]);
                if (p > bestp) {
                    best = i;
                    bestp = p;
                }
            }
            return [models[best].name, bestp];
        }
    }

    var make_recog = function(hmmdef) {
        // XXX handle other types of HMM
        return make_discrete_recog(hmmdef);
    };

    return {
        // utility functions
        tolog: tolog,
        fromlog: fromlog,
        // main recognizer
        make_recog: make_recog
    };
});
