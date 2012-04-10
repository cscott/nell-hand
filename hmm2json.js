#!/usr/bin/node

var requirejs = require('requirejs');

// ometa bug workaround; see below.
var Array_reduce = Array.prototype.reduce;

requirejs(['commander', 'fs', 'parse', './version'], function(program, fs, parse, version) {

    // workaround bug in ometa which redefines Array.reduce in a way that
    // breaks commander
    Array.prototype.reduce = Array_reduce;

    program
        .version(version)
        .usage('[options] <hmmfile> ... <hmmfile>')
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

    // concatenate all the input files
    var inputFiles = [];
    program.args.forEach(function(filename) {
        inputFiles.push(fs.readFileSync(filename, 'utf-8'));
    });
    inputFiles = inputFiles.join('\n');

    // 'parse' is a promise
    parse.then(function(parser) {
        return parser(inputFiles, 'top'); // another promise
    }).then(function(result) {
        var jsonString = JSON.stringify(result);
        output.write(jsonString);
        if (program.output) output.end();
    }).end();
});
