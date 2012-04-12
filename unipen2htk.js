#!/usr/bin/node
// running with node 0.7.5, installed 'commander' and 'progress'
// uses typed arrays, which landed in node 0.5.5.
var requirejs = require('requirejs');

requirejs(['commander', 'fs', 'progress', './point', './features', './version'],
function(program, fs, ProgressBar, Point, Features, version) {

var CANVAS_RESOLUTION = 100;
var RETINA_FACTOR = 1;
var DOT_SIZE = 1/60;
var RESAMPLE_HERTZ = 100; // sample rate written into parameter file

program
    .version(version)
    .usage('[options] <json input file>')
    .option('-P, --parmdir <output dir>', 'directory for parameter file output',
            null)
    .option('-M, --mlf <filename>', 'label file for parameter data',
            null)
    .option('-H, --html <filename>', 'html file output for previewing data',
            null)
    .option('-T, --train <number>', 'omit 1 in <number> examples from training set', Number, 0)
    .option('-S, --script <filename>', 'list of parameter files for training', null)
    .option('-Q, --qualscript <filename>', 'list of parameter files *not* used for training', null)
    .option('-A, --allographs <number>', 'Randomly spread the input into <number> allograph classes', Number, 1)
    .parse(process.argv);

var input_file = program.args[0];
var data = JSON.parse(fs.readFileSync(input_file, 'utf-8'));

var mklogfunc = function(what, opt_filename) {
    var fd = -1;
    if (opt_filename) {
        fd = fs.openSync(opt_filename, 'w');
    }
    var f = function(s) {
        if (fd >= 0) {
            fs.writeSync(fd, s+"\n", null, 'utf8');
        }
    };
    f.close = function() {
        if (fd >= 0) {
            fs.closeSync(fd);
            console.log(what+": "+opt_filename);
        }
    };
    return f;
};

var p = mklogfunc('HTML output', program.html);
p("<!DOCTYPE HTML>");
p("<html><head><title>Character Visualization</title>");
p("<style type=\"text/css\">");
p("canvas { width: "+CANVAS_RESOLUTION+"px; height: "+CANVAS_RESOLUTION+"px; border: 1px solid #ccc; }");
p("</style></head>");
p("<body><h1>Character Visualization</h1>");
//p('Version', data.version);
p("<p>" + data.set.length + " characters, ");
p("avg <span id='avglen'></span> samples.</p>");

var m = mklogfunc('Label file', program.mlf);
var ma = mklogfunc('Label file (random allographs)',
                   (program.allographs>1 && program.mlf) ?
                   program.mlf + ".allograph" : null);
m("#!MLF!#");
ma('#!MLF!#');

var s = mklogfunc('Script file', program.script);
var q = mklogfunc('Qualification file', program.qualscript);


var canvas_id = 0;
var draw_letter = function(data_set, caption) {
    // data_set should be normalized (range [0,1], dups removed)
    var id = "c" + (canvas_id++);
    p("<canvas id="+JSON.stringify(id)+" title="+JSON.stringify(caption)+"></canvas>");
    p("<script type=\"text/javascript\">");
    p("(function() { ");
    p("  var canvas = document.getElementById("+JSON.stringify(id)+");");
    p("  canvas.width = canvas.height = "+CANVAS_RESOLUTION*RETINA_FACTOR+";");
    p("  var ctx = canvas.getContext(\"2d\");");
    var norm = function(pt) {
        return new Point(   pt.x *CANVAS_RESOLUTION*RETINA_FACTOR,
                         (1-pt.y)*CANVAS_RESOLUTION*RETINA_FACTOR,
                            pt.isUp);
    };
    // set ctx.stroke style, whatever that property is.
    data_set.strokes.forEach(function(stroke) {
        p("ctx.beginPath();");
        stroke.map(norm).forEach(function(pt, i) {
            if (i==0 || pt.isUp) {
                p("ctx.moveTo("+pt.x+","+pt.y+");");
            } else {
                p("ctx.lineTo("+pt.x+","+pt.y+");");
            }
        });
        p("ctx.stroke();");
    });

    // points
    p("ctx.beginPath();");
    data_set.strokes.forEach(function(stroke) {
        stroke.map(norm).forEach(function(pt) {
            p("ctx.arc("+pt.x+","+pt.y+","+
              (DOT_SIZE*CANVAS_RESOLUTION*RETINA_FACTOR)+","+
              "0,2*Math.PI,true);");
        });
    });
    p("ctx.fill();");

    // label data
    p("  ctx.fillStyle=\"#008\";");
    p("  ctx.font=\""+(10*RETINA_FACTOR)+"px sans-serif\";");
    p("  ctx.fillText("+JSON.stringify(data_set.source+" "+data_set.start)+", 0, 10, "+CANVAS_RESOLUTION*RETINA_FACTOR+");");
    p("})();");
    p("</script>");
};

// okay, draw the letters!
var avg_len = 0, avg_cnt = 0, min_len, max_len;
var bar = new ProgressBar('Writing features: [:bar] :percent :etas',
                          { total: data.set.length, width: 30 });
var featmin, featmax;
for (var i=0, n=0; i<data.set.length; i++, bar.tick()) {
    var label = data.set[i].name;
    Features.normalize(data.set[i]);
    draw_letter(data.set[i], "Unipen "+i);

    Features.smooth(data.set[i]);
    Features.singleStroke(data.set[i]);
    //draw_letter(data.set[i], "Smoothed "+i);

    Features.equidist(data.set[i]);
    draw_letter(data.set[i], "Resampled "+i);
    if (data.set[i].strokes[0].length===0) continue;

    avg_len += data.set[i].strokes[0].length;
    avg_cnt += 1;

    Features.features(data.set[i]);
    if (data.set[i].features.length===0) continue;
    if (i===0) {
        min_len = data.set[i].features.length;
        max_len = data.set[i].features.length;
        featmax = data.set[i].features[0].slice(0);
        featmin = data.set[i].features[0].slice(0);
    }
    min_len = Math.min(min_len, data.set[i].features.length);
    max_len = Math.max(max_len, data.set[i].features.length);
    data.set[i].features.forEach(function(featvect) {
        featvect.forEach(function(f, j) {
            if (f > featmax[j]) { featmax[j] = f; }
            if (f < featmin[j]) { featmin[j] = f; }
        });
    });

    if (!program.parmdir) continue;

    // Make 12-byte header
    var nfeat = data.set[i].features.length;
    if (nfeat === 0) continue; // hm, strange.
    var featvlen = data.set[i].features[0].length;

    var hbuf = new ArrayBuffer(12);
    // nSamples         - number of samples in file (4-byte integer)
    new Uint32Array(hbuf, 0)[0] = nfeat;
    // sampPeriod       - sample period in 100ns units (4-byte integer)
    new Uint32Array(hbuf, 4)[0] = Math.round(10000000/RESAMPLE_HERTZ);
    // sampSize         - number of bytes per sample (2-byte integer)
    new Uint16Array(hbuf, 8)[0] = featvlen * 4;
    // parmKind         - a code indicating the sample kind (2-byte integer)
    new Uint16Array(hbuf,10)[0] = 9; // USER: user defined sample kind

    // Make a Float32 array w/ the feature vector.
    var fbuf = new ArrayBuffer(4*nfeat*featvlen);
    var featv = new Float32Array(fbuf);
    data.set[i].features.forEach(function (fv, j) {
        featv.set(fv, j*featvlen);
    });

    // convert to node-native buffer type and write file
    var filename = "" + i;
    while (filename.length < 4) { filename = "0" + filename; }
    var parm_fd = fs.openSync(program.parmdir+"/"+filename+".htk", 'w');
    var w = function(arraybuf) {
        var b = new Buffer(new Uint8Array(arraybuf));
        fs.writeSync(parm_fd, b, 0, b.length, null);
    };
    w(hbuf);
    w(fbuf);
    fs.closeSync(parm_fd);

    m('"'+program.parmdir+'/'+filename+'.lab"');
    ma('"'+program.parmdir+'/'+filename+'.lab"');
    if (program.allographs===1) {
        m(label);
    } else {
        var a = Math.floor(i * program.allographs / data.set.length);
        ma(label+(1+a)+"\t"+label);
        for (var j=0; j<program.allographs; j++) {
            if (j>0) m('///');
            m(label+(j+1)+"\t"+label);
        }
    }
    m('.');
    ma('.');

    if (program.train === 0 || (n % program.train !== 0)) {
        s(program.parmdir+'/'+filename+'.htk');
    } else {
        q(program.parmdir+'/'+filename+'.htk');
    }
    n++; // keep separate count just in case we disqualify particular files
}
avg_len /= avg_cnt;
p("<script type=\"text/javascript\">");
p("document.getElementById('avglen').innerHTML='"+avg_len+"';");
p("</script>");

// done w/ progress bar.
console.log("\r                                                              ");
// some stats
p.close();
m.close();
ma.close();
s.close();
q.close();

if (program.parmdir) {
    console.log("Parameter files in: "+program.parmdir);
}
console.log("Min/Avg/Max # features: "+min_len+"/"+Math.round(avg_len)+"/"+max_len);
console.log("Min feat: "+featmin);
console.log("Max feat: "+featmax);

});
