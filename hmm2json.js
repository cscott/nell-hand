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
        .option('-o <outfile>', 'Output to the specified file (default stdout)',
                null)
        .parse(process.argv);

    // 'parse' is a promise
    parse.then(function(parser) {
        return parser('53+15', 'exp'); // another promise
    }).then(function(result) {
        console.log(result);
    }).end();
});
