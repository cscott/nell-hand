#!/usr/bin/node

var requirejs = require('requirejs');

requirejs(['commander', 'fs', 'q', './features', './hmm', './version'], function(program, fs, Q, Features, HMM, version) {

    program
        .version(version)
        .usage('[options] <hmmdef>.json <input file 1>.htk <input file 2>.htk..')
        .option('-o, --output <outfile>',
                'Output to the specified file (default stdout)',
                null)
        .option('-S, --script <script file>',
                'File with additional command-line arguments',
                null)
        .parse(process.argv);

    if (program.script) {
        var extra = fs.readFileSync(program.script, 'utf-8').split(/\s+/);
        program.args.push.apply(program.args, extra);
    }
    if (program.args.length===0) {
        console.error('Missing JSON HMM definition');
        return;
    }
    var output = process.stdout;
    if (program.output) {
        output = fs.createWriteStream(program.output, { encoding: 'utf-8' });
    }

    var hmmdef = JSON.parse(fs.readFileSync(program.args.shift(), 'utf-8'));
    var vq_features = null;
    if (hmmdef[0].type==='<codebook>') {
        vq_features = Features.make_vq(hmmdef[0].value);
    }
    var recognizer = HMM.make_recog(hmmdef);

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
    output.write('#!MLF!#\n');
    program.args.forEach(function(filename) {
        output.write(JSON.stringify(filename)+'\n');
        // read HTK file.
        var data_set = readHTK(filename);
        // add missing features
        Features.delta_and_accel(data_set);
        if (vq_features) {
            vq_features(data_set);
        }
        // recognize!
        var result = recognizer(data_set);
        output.write(result);
        output.write('\n.\n');
    });
    if (program.output) output.end();
});
