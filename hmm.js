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

    var extract_models = function(hmmdef, process) {
        var globals = {};
        var models = [];
        var mixes = {};

        for (var i=0; i<hmmdef.length; i++) {
            switch(hmmdef[i].type) {
            case '<comment>':
                /* ignore */
                break;
            case '<codebook>':
                process.codebook(hmmdef[i].name, globals, hmmdef[i].value);
                break;
            case '~o':
                globals = omerge(globals, hmmdef[i].value);
                break;
            case '~m':
                process.mix(hmmdef[i].name, globals, hmmdef[i].value);
                break;
            case '~h':
                models.push(process.model(hmmdef[i].name, globals,
                                          hmmdef[i].value));
                break;
            default:
                // ignore other definitions for now.
                // XXX in the future we might want to expand macro references
                break;
            }
        }
        return models;
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

    var process_transp = function(def, states) {
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
    };

    var best_model = function(models, maxp) {
        var best=0, bestp = maxp(models[0]), p;
        for (var i=1; i<models.length; i++) {
            p = maxp(models[i]);
            if (p > bestp) {
                best = i;
                bestp = p;
            }
        }
        return [models[best].name, bestp];
    };

    var make_discrete_recog = function(hmmdef) {
        var vq_features;
        var process_codebook = function(_, globals, codebook) {
            vq_features = Features.make_vq(codebook);
        };
        var make_model = function(name, globals, def) {
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
            process_transp(def, states);
            // ok, done!
            return { name: name, states: states };
        };
        var models = extract_models(hmmdef, {
            model: make_model,
            codebook: process_codebook
        });
        console.assert(models.length);
        hmmdef = null; // free up unparsed representation

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
            return best_model(models, maxp);
        }
    };

    var make_tied_mix_recog = function(hmmdef) {
        var codebooks = [];
        var make_codebook = function(streamno, name, len, globals) {
            if (!codebooks[streamno])
                codebooks[streamno] = {};
            if (!codebooks[streamno][name]) {
                var c = [];
                for (var i=1; i <= len; i++) {
                    var n = name + '' + i;
                    console.assert(n in globals.MixCodebook);
                    c.push(globals.MixCodebook[n]);
                }
                codebooks[streamno][name] = c;
            }
            return codebooks[streamno][name];
        };
        var make_model = function(name, globals, def) {
            console.assert(globals.CovKind === 'DiagC');//other types unimpl.
            var states = [], i, j;
            // process output probabilities
            states.push({ id: 0, start: true, pred: [] }); /* entry state */
            for (i=2; i < def.NumStates; i++) {
                states.push({
                    id: states.length,
                    output: def.States[i].Streams.map(function(m, j) {
                        console.assert(m.TMix);
                        var len = def.States[i].NumMixes[j];
                        var cb = make_codebook(j, m.TMix.name, len, globals);
                        var ws = expand_weightlist(m.TMix.weights
                                                   .map(function(w) {
                            return [Math.log(w[0]), w[1]];
                        }));
                        console.assert(ws.length === len);
                        return { codebook: cb, weights:  ws };
                    }),
                    // XXX we ignore stream weights
                    weights: def.States[i].SWeights,
                    pred: []
                });
            }
            states.push({ id: states.length, pred: [] }); /* exit state */

            process_transp(def, states);
            return { name: name, states: states };
        };
        var process_mix = function(name, globals, def) {
            var mix = def.Mix;
            if (!globals.MixCodebook) globals.MixCodebook = {};
            globals.MixCodebook[name] = mix;
            // fill in GConst: (2pi)^n * |COV|
            // console.log('GConst (old)', mix.GConst);
            var gconst = Math.log(2*Math.PI) * mix.Variance.length;
            for (var i=0; i<mix.Variance.length; i++) {
                gconst += Math.log(mix.Variance[i]);
            }
            mix.GConst = gconst;
            // console.log('GConst (new)', gconst);
        };
        var models = extract_models(hmmdef, {
            model: make_model,
            mix: process_mix
        });
        console.assert(models.length);
        hmmdef = null; // free up original representation

        // we only support a single codebook per stream.
        codebooks = codebooks.map(function(o, i) {
            var n = Object.getOwnPropertyNames(o);
            console.assert(n.length === 1);
            return o[n[0]];
        });

        var compute_gaussians = function(data_set) {
            console.assert(codebooks.length <= 3);
            return data_set.features.map(function(_, t) {
                // "for each observation..."
                var input = [ data_set.features[t] ];
                if (codebooks.length > 1)
                    input.push( data_set.deltas[t] );
                if (codebooks.length > 2)
                    input.push( data_set.accels[t] );

                return input.map(function(v, i) { // "for each stream..."
                    return codebooks[i].map(function(mix) {
                        // N(o;u,E)=e^((-1/2)*(o-u)'*E^-1*(o-u))/(GConst)^(-1/2)
                        // [HTK book 7.2] -- logarithmic math
                        console.assert(v.length === mix.Mean.length);
                        var acc = 0;
                        for (var j=0; j<v.length; j++) {
                            var o_minus_mean = v[j] - mix.Mean[j];
                            acc += o_minus_mean*o_minus_mean / mix.Variance[j];
                        }
                        return (acc + mix.GConst) / -2;
                    });
                });
            });
        };

        var make_maxp = function(input) {
            var phi = function(phi, state, t) {
                var i, j;
                if (state.start) {
                    return (t===0) ? 0 : -Infinity; /* base case */
                }
                if (t===0) return -Infinity;
                if (state.pred.length===0) return -Infinity; /* unusual */

                // compute probability of emitting signal o_t in this state
                var o_t = input[t-1];
                var b_j = 0;
                // XXX we're ignoring stream weights
                for (j = 0; j<o_t.length; j++) {
                    // find maximum weighted gaussian
                    var best = 0, bestg= o_t[j][0] + state.output[j].weights[0];
                    for (i=0; i<state.output[j].weights.length; i++) {
                        var g = o_t[j][i] + state.output[j].weights[i];
                        if (g > bestg) { bestg = g; best = i; }
                    }
                    // sum all the gaussians, using the identity:
                    // log(a + c) = log(a) + log(1 + c/a)
                    //            = log(a) + log(1 + exp(log(c) - log(a)))
                    b_j += bestg;
                    var partial = 1;
                    for (i=0; i<state.output[j].weights.length; i++) {
                        if (i === best) continue;
                        var g = o_t[j][i] + state.output[j].weights[i];
                        partial += Math.exp(g - bestg);
                    }
                    b_j += Math.log(partial);
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
            // take data set and evaluate all mixes in the codebook
            var maxp = make_maxp(compute_gaussians(data_set));
            return best_model(models, maxp);
        };
    };

    var make_recog = function(hmmdef) {
        var saw_codebook = false, saw_v = false, saw_nontied = false;
        extract_models(hmmdef, {
            model: function(name, globals, def) {
                if (globals.ParmKind.extra.indexOf('V') >= 0) saw_v = true;
                // for all states, are all the stream models tied?
                for (var i=2; i < def.NumStates; i++) {
                    var state = def.States[i];
                    for (var j=0; j < state.NumMixes.length; j++) {
                        var stream = state.Streams[j];
                        if (!('TMix' in stream)) saw_nontied = true;
                    }
                }
                return null;
            },
            codebook: function() { saw_codebook = true; },
            mix: function(name, globals, def) { },
        });
        // ok, figure out what type of HMM definition this is.
        if (saw_codebook && saw_v) {
            return make_discrete_recog(hmmdef);
        } else if ((!saw_v) && (!saw_nontied)) {
            return make_tied_mix_recog(hmmdef);
        } else {
            // XXX handle other types of HMM
            console.assert(false);
        }
    };

    return {
        // utility functions
        tolog: tolog,
        fromlog: fromlog,
        // main recognizer
        make_recog: make_recog
    };
});
