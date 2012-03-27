#!/usr/bin/node
// running with node 0.7.5, installed 'commander' and 'progress'

var CANVAS_RESOLUTION = 100;
var RETINA_FACTOR = 1;
var DOT_SIZE = 1/40;
var SMOOTH_N = 3, SMOOTH_ALPHA = .25;
var RESAMPLE_INTERVAL = 1/13;

var program = require('commander');
var fs = require('fs');

program
    .version('0.1')
    .parse(process.argv);

var input_file = program.args[0];
var data = JSON.parse(fs.readFileSync(input_file, 'utf-8'));

var p = function(s) {
    console.log(s);
};

p("<!DOCTYPE HTML>");
p("<html><head><title>Character Visualization</title>");
p("<style type=\"text/css\">");
p("canvas { width: "+CANVAS_RESOLUTION+"px; height: "+CANVAS_RESOLUTION+"px; border: 1px solid #ccc; }");
p("</style></head>");
p("<body><h1>Character Visualization</h1>");
//p('Version', data.version);
p("<p>" + data.set.length + "characters, ");
p("avg <span id='avglen'></span> samples.</p>");

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

    // use correct aspect ratio
    var size = bbox.size();
    size = Math.max(size.width, size.height);
    var norm = function(pt) {
        // map to [0-1], y=0 at bottom (math style)
        var x = (pt.x - bbox.tl.x) / size;
        var y = (pt.y - bbox.tl.y) / size;
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
for (var i=0; i<data.set.length; i++) {
    normalize(data.set[i]);
    draw_letter(data.set[i], "Unipen");

    smooth(data.set[i]);
    singleStroke(data.set[i]);
    //draw_letter(data.set[i], "Smoothed");

    equidist(data.set[i], RESAMPLE_INTERVAL);
    draw_letter(data.set[i], "Resampled");

    avg_len += data.set[i].strokes[0].length;
}
avg_len /= data.set.length;
p("<script type=\"text/javascript\">");
p("document.getElementById('avglen').innerHTML='"+avg_len+"';");
p("</script>");
