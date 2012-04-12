#!/usr/bin/node --max-old-space-size=2000

var requirejs = require('requirejs');

// ometa bug workaround; see below.
var Array_reduce = Array.prototype.reduce;

requirejs(['commander', 'fs', 'q', 'parse', './version'], function(program, fs, Q, parse, version) {

    // workaround bug in ometa which redefines Array.reduce in a way that
    // breaks commander
    Array.prototype.reduce = Array_reduce;

    program
        .version(version)
        .usage('[options] <hmmfile> ... <hmmfile>')
        .option('-c, --codebook <cbfile>',
                'Include the specified VQ codebook',
                null)
        .option('-o, --output <outfile>',
                'Output to the specified file (default stdout)',
                null)
        .parse(process.argv);

    if (program.args.length===0 && !program.codebook) {
        console.error("No input.");
        return;
    }
    var output = process.stdout;
    if (program.output) {
        output = fs.createWriteStream(program.output, { encoding: 'utf-8' });
    }

    // read the codebook (if there is one)
    var codebook = Q.call(function(){});
    if (program.codebook) {
        codebook = Q.ncall(fs.readFile, fs, program.codebook, 'utf-8');
    }

    // concatenate all the input files
    var inputFiles = Q.all(program.args.map(function(filename) {
        return Q.ncall(fs.readFile, fs, filename, 'utf-8');
    }));

    // 'parse' is a promise
    Q.all([codebook, inputFiles, parse])
        .spread(function(codebook, inputFiles, parser) {
            var cb_promise = Q.call(function(){});
            if (program.codebook)
                cb_promise = parser(codebook, 'codebook');
            var hmm_promise = parser(inputFiles.join('\n'), 'top');

            return Q.all([cb_promise, hmm_promise]);
        }).spread(function(cb_result, hmm_result) {
            if (program.codebook) {
                hmm_result.unshift({ type: "<codebook>", value: cb_result });
            }
            var jsonString = JSON.stringify(hmm_result);
            output.write(jsonString);
            if (program.output) output.end();
        }).end();
});
