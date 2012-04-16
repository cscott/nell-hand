#!/usr/bin/node

var requirejs = require('requirejs');

requirejs(['commander', 'fs', 'q', './features', './hmm', './version'], function(program, fs, Q, Features, HMM, version) {

    program
        .version(version)
        .usage('[options] <hmmdef>.json <input file 1>.htk <input file 2>.htk..')
        .option('-o, --output <outfile>',
                'Output to the specified file (default stdout)',
                null)
        .option('-A, --strip_allograph', "Strip allograph suffix from result")
        .option('-S, --script <script file>',
                'File with additional command-line arguments',
                null)
        .option('-T, --time', "Don't emit output, just time the recognition.")
        .option('-c, --mix_thresh <number>', "Pruning threshold for tied mixtures", Number, 0)
        .parse(process.argv);

    if (program.script) {
        var extra= fs.readFileSync(program.script, 'utf-8').trim().split(/\s+/);
        program.args.push.apply(program.args, extra);
    }
    if (program.args.length===0) {
        console.error('Missing JSON HMM definition');
        return;
    }
    var output = process.stdout;
    if (program.output) {
        if (program.time) {
            console.error("Timing recognition; skipping output.");
        } else {
            output=fs.createWriteStream(program.output, { encoding: 'utf-8' });
        }
    }

    var hmmdef = JSON.parse(fs.readFileSync(program.args.shift(), 'utf-8'));
    var options = {};
    if (program.mix_thresh) { options.mix_thresh = program.mix_thresh; }
    var recognizer = HMM.make_recog(hmmdef, options);

    var readHTK = function(filename) {
        var buffer = fs.readFileSync(filename);
        // XXX THIS CODE ASSUMES MACHINE IS LITTLE-ENDIAN.
        var nSamples = buffer.readUInt32LE(0);
        var sampSize = buffer.readUInt16LE(8);
        var parmKind = buffer.readUInt16LE(10);
        var offset = 12;
        // XXX ASSUMES THAT INPUT IS USER, NOT USER_D_A OR DISCRETE
        console.assert(parmKind === 9);
        var features = [];
        for (var i=0; i<nSamples; i++) {
            features[i] = [];
            for (var j=0; (j*4) < sampSize; j++, offset+=4) {
                features[i][j] = buffer.readFloatLE(offset);
            }
        }
        return { features: features };
    };

    // read the rest of the files.
    var do_read = function(filename) {
        // read HTK file.
        return [filename, readHTK(filename)];
    };
    var do_delta = function(args) {
        var filename = args[0], data_set = args[1];
        // add missing features
        Features.delta_and_accel(data_set);
        return args;
    };
    var do_recog = function(args) {
        var filename = args[0], data_set = args[1];
        // recognize!
        return [filename, recognizer(data_set)];
    };
    if (program.time) {
        console.log(program.args.length+" input files.");

        console.time('HTK file input');
        var input = program.args.map(do_read);
        console.timeEnd('HTK file input');

        console.time('Delta computation');
        input = input.map(do_delta);
        console.timeEnd('Delta computation');

        console.time('Recognition time');
        var results = input.map(do_recog);
        console.timeEnd('Recognition time');

        // skip output step.
    } else {
        output.write('#!MLF!#\n');
        program.args.forEach(function(filename) {
            var result = do_recog(do_delta(do_read(filename)))[1];
            output.write(JSON.stringify(filename)+'\n');
            var model = result[0], score = result[1];
            if (program.strip_allograph) {
                model = model.replace(/[0-9]+$/, '');
            }
            output.write(model+"\t"+score);
            output.write('\n.\n');
        });
    }
    if (program.output && !program.time) output.end();
});
