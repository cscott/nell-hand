#!/usr/bin/node

var requirejs = require('requirejs');

requirejs(['commander', 'fs', './version'], function(program, fs, version) {

    program
        .version(version)
        .usage('[options] <json file>')
        .option('-o, --output <outfile>',
                'Output to the specified file (default stdout)',
                null)
        .parse(process.argv);

    if (program.args.length===0) {
        console.error("No input.");
        return;
    }
    var output = process.stdout;
    if (program.output) {
        output = fs.createWriteStream(program.output, { encoding: 'utf-8' });
    }
    var p = function(s) {
        output.write(s+'\n');
    };
    var string = function(s) {
        return JSON.stringify(s);
    };
    var array = function(a) {
        return a.length + ' ' +a.map(function(e){return ''+e;}).join(' ');
    };

    var input = JSON.parse(fs.readFileSync(program.args[0], 'utf-8'));
    var checkMacro;
    var emitMacro, emitMacroRef, emitState, emitTransP, emitDuration;
    var emitStream, emitWeightList, emitMixture, emitMixPDF, emitMean, emitCov;
    var emitVariance, emitInvCovar, emitLLTCovar, emitXform;
    var emitMatrix;

    checkMacro = function(o) {
        if (!o.macro) return false;
        var m = o.macro;
        p(m.type+' '+string(m.name));
        return true;
    }

    emitMacro = function(m) {
        var firstline = m.type;
        if (m.name) {
            firstline += ' ' + string(m.name);
        }
        if (m.type === '~h' && !m.name) {
            firstline = '';
        }
        p(firstline);
        // dispatch to the appropriate emit function
        emitMacro[m.type](m.value);
    };
    emitMacro["~o"] = function(global) {
        if (global.HmmSetId) {
            p('<HmmSetId> '+string(global.HmmSetId));
        }
        if (global.StreamInfo) {
            p('<StreamInfo> '+array(global.StreamInfo));
        }
        if (global.VecSize) {
            p('<VecSize> '+global.VecSize);
        }
        if (global.ProjSize) {
            p('<ProjSize> '+global.ProjSize);
        }
        if (global.InputXform) {
            p('<InputXform>');
            inputXform(global.InputXform);
        }
        if (global.ParentXform) {
            p('<ParentXform>');
            p('~a '+string(global.ParentXform.macro));
        }
        if (global.CovKind) {
            p('<'+global.CovKind+'>');
        }
        if (global.DurKind) {
            p('<'+global.DurKind+'>');
        }
        if (global.ParmKind) {
            var pks = (function(pk) {
                var s = pk.base;
                for (var i=0; i<pk.extra.length; i++) {
                    s += '_' + pk.extra[i];
                }
                return s.toUpperCase();
            })(global.ParmKind);
            p('<'+pks+'>');
        }
    };
    emitMacro["~h"] = function(h) {
        p('<BeginHMM>');
        emitMacro["~o"](h); // global opts, if any.
        p('<NumStates> '+h.NumStates);
        for (var i=1; i <= h.NumStates; i++) {
            if (i in h.States) {
                emitState(i, h.States[i]);
            }
        }
        emitTransP(h.TransP);
        if (h.Duration) {
            emitDuration(h.Duration);
        }
        p('<EndHMM>');
    };
    emitMacro['~s'] = function(m) { emitState(-1, m); };
    emitState = function(n, state) {
        if (n > 0) {
            p('<State> '+n);
        }
        if (checkMacro(state)) return;
        if (state.NumMixes) {
            p('<NumMixes> '+state.NumMixes);
        }
        if (state.SWeights) {
            p('<SWeights> '+array(state.SWeights));
        }
        for (var i=0; i<state.Streams.length; i++) {
            emitStream(i+1, state.Streams[i]);
        }
        if (state.Duration) {
            emitDuration(state.Duration);
        }
    };
    emitMacro["~t"] = function(m) { emitTransP(m.TransP); };
    emitTransP = function(tp) {
        if (checkMacro(tp)) return;
        p('<TransP>');
        emitMatrix(tp);
    };
    emitMacro["~d"] = function(m) { emitDuration(m.Duration); };
    emitDuration = function(d) {
        if (checkMacro(d)) return;
        p('<Duration> '+array(d));
    };
    emitStream = function(n, s) {
        p('<Stream> '+n);
        if (s.Mixtures) {
            for (var i=0; i<s.Mixtures.length; i++) {
                emitMixture(i+1, s.Mixtures[i]);
            }
        }
        if (s.TMix) {
            p('<TMix> '+string(s.TMix.name));
            emitWeightList(s.TMix.weights);
        }
        if (s.DProb) {
            p('<DProb>');
            emitWeightList(s.DProb);
        }
    };
    emitWeightList = function(wl) {
        var r = [];
        for (var i=0; i<wl.length; i++) {
            r.push(wl[i][0]);
            if (wl[i][1] > 1) {
                r.push('*');
                r.push(wl[i][1]);
            }
            r.push(' ');
        }
        p(r.join(''));
    };
    emitMixture = function(n, mix) {
        p('<Mixture> '+n+' '+mix.Weight);
        emitMixPDF(mix.Mix);
    };
    emitMacro["~m"] = function(m) { emitMixPDF(m.Mix); };
    emitMixPDF = function(mix) {
        if (checkMacro(mix)) return;
        emitMean(mix.Mean);
        emitCov(mix);
        if (mix.GConst) {
            p('<GConst> '+mix.GConst);
        }
    };
    emitMacro['~u'] = function(m) { emitMean(m.Mean); };
    emitMean = function(mean) {
        if (checkMacro(mean)) return;
        p('<Mean> '+array(mean));
    };

    emitCov = function(cov) {
        if (cov.Variance) emitVariance(cov.Variance);
        if (cov.InvCovar) emitInvCovar(cov.InvCovar);
        if (cov.LLTCovar) emitLLTCovar(cov.LLTCovar);
    };
    emitMacro['~v'] = function(m) { emitVariance(m.Variance); };
    emitVariance = function(v) {
        if (checkMacro(v)) return;
        p('<Variance> '+array(v));
    };
    emitMacro['~i'] = function(m) { emitInvCovar(m.InvCovar); };
    emitInvCovar = function(i) {
        if (checkMacro(i)) return;
        p('<InvCovar>');
        emitMatrix(i);
    };
    emitMacro['~c'] = function(m) { emitLLTCovar(m.LLTCovar); };
    emitLLTCovar = function(l) {
        if (checkMacro(l)) return;
        p('<LLTCovar>');
        emitMatrix(l);
    };

    emitMacro['~x'] = function(m) { emitXform(m.Xform); };
    emitXform = function(x) {
        if (checkMacro(x)) return;
        p('<Xform>');
        emitMatrix(x);
    };

    emitMatrix = function(m) {
        p(m.rows);
        if (m.type==='rect') p(m.cols);
        var i=0;
        for (var r=0; r<m.rows; r++) {
            var line = [];
            for (var c=0; c<m.cols; c++) {
                if (m.type==='tri' && (c < r)) {
                    line.push(' ');
                } else {
                    line.push(''+m.entries[i++]);
                }
            }
            p(line.join(' '));
        }
    };

    // write out macro definitions in order
    for (var i=0; i<input.length; i++) {
        emitMacro(input[i]);
    }
    // done.
    if (program.output) output.end();
});
