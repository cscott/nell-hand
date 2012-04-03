#!/usr/bin/node
// running with node 0.7.5, installed 'commander' and 'progress'
// uses typed arrays, which landed in node 0.5.5.

var CANVAS_RESOLUTION = 100;
var RETINA_FACTOR = 1;
var DOT_SIZE = 1/40;
var SMOOTH_N = 3, SMOOTH_ALPHA = .25;
var RESAMPLE_INTERVAL = 1/7;//1/10;
var RESAMPLE_HERTZ = 30; // sample rate written into parameter file

var program = require('commander');
var fs = require('fs');
var ProgressBar = require('progress');

program
    .version('0.1')
    .usage('[options] <json input file>')
    .option('-P, --parmdir <output dir>', 'directory for parameter file output',
            null)
    .option('-M, --mlf <filename>', 'label file for parameter data',
            null)
    .option('-H, --html <filename>', 'html file output for previewing data',
            null)
    .option('-T, --train <number>', 'omit 1 in <number> examples from training set', Number, 0)
    .option('-S, --script <filename>', 'list of parameter files for training', null)
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
m("#!MLF!#");

var s = mklogfunc('Script file', program.script);

var Point = function(x, y, isUp) {
    this.x = x; this.y = y; this.isUp = isUp || false;
};
Point.prototype = {
    clone: function() { return new Point(this.x, this.y, this.isUp); },
    equals: function(p) { return Point.equals(this, p); },
    dist: function(p) { return Point.dist(this, p); },
    interp: function(p, amt) { return Point.interp(this, p, amt); }
};
Point.equals = function(a, b) {
    return (a.x === b.x) && (a.y === b.y) && (a.isUp === b.isUp);
};
Point.dist = function(a, b) {
    var dx = a.x - b.x, dy = a.y - b.y;
    return Math.sqrt(dx*dx + dy*dy);
};
Point.interp = function(p1, p2, amt) {
    var x = p1.x + amt*(p2.x - p1.x);
    var y = p1.y + amt*(p2.y - p1.y);
    return new Point(x, y, p2.isUp);
};

var Box = function(tl, br) {
    this.tl = tl;
    this.br = br;
};
Box.prototype = {
    unionPt: function(pt) {
        if (pt.x < this.tl.x) { this.tl.x = pt.x; }
        if (pt.y < this.tl.y) { this.tl.y = pt.y; }
        if (pt.x > this.br.x) { this.br.x = pt.x; }
        if (pt.y > this.br.y) { this.br.y = pt.y; }
    },
    union: function(box) {
        this.unionPt(box.tl);
        this.unionPt(box.br);
    },
    size: function() {
        return { width: this.br.x - this.tl.x,
                 height: this.br.y - this.tl.y };
    }
};
Box.fromPts = function(pts) {
    // pts must have at least one element
    var b = new Box(pts[0].clone(), pts[0].clone());
    pts.forEach(function(p) { b.unionPt(p); });
    return b;
};

var normalize = function(data_set) {
    var ppmm = data_set.ppmm;
    var mkpt = function(p) { return new Point(p[0], p[1]); };

    // remove dups
    data_set.strokes = data_set.strokes.map(function(stroke) {
        stroke = stroke.map(mkpt);
        var nstrokes = [stroke[0]];
        for (var i=1; i<stroke.length; i++) {
            if (stroke[i].equals(stroke[i-1]))
                continue;
            nstrokes.push(stroke[i]);
        }
        return nstrokes;
    });

    // find bounding box
    var strokeBBs = data_set.strokes.map(function(stroke) {
        return Box.fromPts(stroke);
    });
    var bbox = strokeBBs[0];
    strokeBBs.forEach(function(bb) { bbox.union(bb); });

    // use correct aspect ratio (including correcting for ppmm differences)
    var size = bbox.size();
    size = Math.max(size.width/ppmm.x, size.height/ppmm.y);/* in mm */
    var norm = function(pt) {
        // map to [0-1], y=0 at bottom (math style)
        var x = (pt.x - bbox.tl.x) / (ppmm.x * size);
        var y = (pt.y - bbox.tl.y) / (ppmm.y * size);
        return new Point(x, y);
    };
    // remove dups
    data_set.strokes = data_set.strokes.map(function(stroke) {
        return stroke.map(norm);
    });
};

var smooth = function(data_set) {
    data_set.strokes = data_set.strokes.map(function(stroke) {
        var nstroke = [];
        for (var i=0; i<stroke.length; i++) {
            var acc = new Point(stroke[i].x * SMOOTH_ALPHA,
                                stroke[i].y * SMOOTH_ALPHA );
            var n = SMOOTH_N;
            // [0, 1, 2, 3, 4 ] .. N = 2, length=5
            while (n>0 && (i<n || i>=(stroke.length-n)))
                n--;
            for (var j=1; j<=n; j++) {
                acc.x += stroke[i-j].x + stroke[i+j].x;
                acc.y += stroke[i-j].y + stroke[i+j].y;
            }
            acc.x /= (2*n + SMOOTH_ALPHA);
            acc.y /= (2*n + SMOOTH_ALPHA);
            nstroke.push(acc);
        }
        return nstroke;
    });
};

var singleStroke = function(data_set) {
    var nstroke = [];
    data_set.strokes.forEach(function(stroke) {
        // add "pen up" stroke.
        var first = stroke[0];
        nstroke.push(new Point(first.x, first.y, true/*up!*/));
        for (var j = 1; j < stroke.length; j++) {
            nstroke.push(stroke[j]);
        }
    });
    data_set.strokes = [ nstroke ];
};
var equidist = function(data_set, dist) {
    console.assert(data_set.strokes.length===1);
    var stroke = data_set.strokes[0];
    var nstroke = [];
    var last = stroke[0];
    var d2next = 0;
    stroke.forEach(function(pt) {
        var d = Point.dist(last, pt);

        while (d2next <= d) {
            var amt = (d===0)?0:(d2next/d);
            nstroke.push(Point.interp(last, pt, amt));
            d2next += dist;
        }
        d2next -= d;
        last = pt;
    });
    // XXX: what should we do with the last point?
    data_set.strokes = [ nstroke ];
};

var features = function(data_set) {
    var points = data_set.strokes[0];
    var features = points.map(function() { return []; });
    for (var i=0; i<points.length; i++) {
        var m2 = points[(i<2) ? 0 : (i-2)];
        var m1 = points[(i<1) ? 0 : (i-1)];
        var pt = points[i];
        var p1 = points[((i+1)<points.length) ? (i+1) : (points.length-1)];
        var p2 = points[((i+2)<points.length) ? (i+2) : (points.length-1)];

        var dx1 = p1.x - m1.x, dy1 = p1.y - m1.y;
        var ds1 = Math.sqrt(dx1*dx1 + dy1*dy1);

        var dx2 = p2.x - m2.x, dy2 = p2.y - m2.y;
        var ds2 = Math.sqrt(dx2*dx2 + dy2*dy2);

        var bb = Box.fromPts([ m2, m1, pt, p1, p2 ]).size();
        var L = m2.dist(m1) + m1.dist(pt) + pt.dist(p1) + p1.dist(p2);

        // http://mathworld.wolfram.com/Point-LineDistance2-Dimensional.html
        var dist2line = function(pp) {
            // x0 = pp.x ; x1 = m2.x ; x2 = p2.x
            // y0 = pp.y ; y1 = m2.y ; y2 = p2.y
            // |(x2-x1)(y1-y0) - (x1-x0)(y2-y1)| / ds2
            // |  dx2 * (m2.y - pp.y) - (m2.x - pp.x)*dy2 | / ds2
            return Math.abs(dx2*(m2.y-pp.y) - dy2*(m2.x-pp.x)) / ds2;
        };
        var d0 = dist2line(m1), d1 = dist2line(pt), d2 = dist2line(p1);
        var dN = 3;
        if (m1.equals(m2)) dN--;
        if (p1.equals(p2)) dN--;

        features[i] = [
            // curvature (fill in in next pass)
            0,
            0,
            // writing direction
            dx1/ds1,
            dy1/ds1,
            // vertical position.
            pt.y,
            // aspect
            (bb.height - bb.width) / (bb.height + bb.width),
            // curliness
            (L / Math.max(bb.height, bb.width)) - 2,
            // linearity
            (d0*d0 + d1*d1 + d2*d2) / dN,
            // slope
            dx2/ds2,
        ];
    }
    // fill in curvature features
    for (var i=0; i<features.length; i++) {
        var m1 = features[(i<1) ? 0 : (i-1)];
        var ft = features[i];
        var p1 = features[((i+1)<features.length)? (i+1) : (features.length-1)];

        var cosm1 = m1[2], sinm1 = m1[3];
        var cosp1 = p1[2], sinp1 = p1[3];
        ft[0] = (cosm1*cosp1) + (sinm1*sinp1);
        ft[1] = (cosm1*sinp1) - (sinm1*cosp1);
    }
    // rescale to normalize to (approximately) [-1,1]
    for (var i=0; i<features.length; i++) {
        features[i][4] = (2 * features[i][4]) - 1;
        features[i][6] = (((features[i][6] + 1) / 3.2) * 2) - 1;
        features[i][7] = (features[i][7] * 100) - 1;
    }
    // save features
    data_set.features = features;
};

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
var avg_len = 0;
var bar = new ProgressBar('Writing features: [:bar] :percent :etas',
                          { total: data.set.length, width: 30 });
var featmin, featmax;
for (var i=0, n=0; i<data.set.length; i++, bar.tick()) {
    var label = data.set[i].name;
    normalize(data.set[i]);
    draw_letter(data.set[i], "Unipen");

    smooth(data.set[i]);
    singleStroke(data.set[i]);
    //draw_letter(data.set[i], "Smoothed");

    equidist(data.set[i], RESAMPLE_INTERVAL);
    draw_letter(data.set[i], "Resampled");

    avg_len += data.set[i].strokes[0].length;

    features(data.set[i]);
    if (i==0) {
        featmax = data.set[i].features[0].slice(0);
        featmin = data.set[i].features[0].slice(0);
    }
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
    m(label);
    m('.');

    if (program.train === 0 || (n % program.train !== 0)) {
        s(program.parmdir+'/'+filename+'.htk');
    }
    n++; // keep separate count just in case we disqualify particular files
}
avg_len /= data.set.length;
p("<script type=\"text/javascript\">");
p("document.getElementById('avglen').innerHTML='"+avg_len+"';");
p("</script>");

// done w/ progress bar.
console.log("\r                                                              ");
// some stats
p.close();
m.close();
s.close();

if (program.parmdir) {
    console.log("Parameter files in: "+program.parmdir);
}
console.log("Average # features: "+avg_len);
console.log("Max feat: "+featmax);
console.log("Min feat: "+featmin);
