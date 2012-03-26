#!/usr/bin/node
// running with node 0.7.5, installed 'commander' and 'progress'

var CANVAS_RESOLUTION = 100;
var RETINA_FACTOR = 1;
var SMOOTH_N = 3, SMOOTH_ALPHA = .25;

var program = require('commander');
var fs = require('fs');

program
    .version('0.1')
    .parse(process.argv);

var input_file = program.args[0];
var data = JSON.parse(fs.readFileSync(input_file, 'utf-8'));

function p(s) {
    console.log(s);
}

p("<!DOCTYPE HTML>");
p("<html><head><title>Character Visualization</title>");
p("<style type=\"text/css\">");
p("canvas { width: "+CANVAS_RESOLUTION+"px; height: "+CANVAS_RESOLUTION+"px; border: 1px solid #ccc; }");
p("</style></head>");
p("<body><h1>Character Visualization</h1>");
//p('Version', data.version);
p("<p>" + data.set.length + "samples</p>");

function normalize(data_set) {
    function mkpt(p) { return { x:p[0], y:p[1] }; }

    // remove dups
    data_set.strokes = data_set.strokes.map(function(stroke) {
        stroke = stroke.map(mkpt);
        var nstrokes = [stroke[0]];
        for (var i=1; i<stroke.length; i++) {
            if (stroke[i].x == stroke[i-1].x &&
                stroke[i].y == stroke[i-1].y)
                continue;
            nstrokes.push(stroke[i]);
        }
        return nstrokes;
    });

    // find bounding box
    // Ugh: this should be a one-liner...
    function minpt(pta, ptb) {
        return {x:Math.min(pta.x, ptb.x), y:Math.min(pta.y, ptb.y)};
    }
    function maxpt(pta, ptb) {
        return {x:Math.max(pta.x, ptb.x), y:Math.max(pta.y, ptb.y)};
    }
    var max = data_set.strokes.map(function(stroke) {
        return stroke.reduce(maxpt);
    }).reduce(maxpt);
    var min = data_set.strokes.map(function(stroke) {
        return stroke.reduce(minpt);
    }).reduce(minpt);

    // use correct aspect ratio
    var x_size = (max.x - min.x), y_size = (max.y - min.y);
    var size = Math.max(x_size, y_size);
    function norm(pt) {
        // map to [0-1], y=0 at bottom (math style)
        var x = (pt.x - min.x) / size;
        var y = (pt.y - min.y) / size;
        return {x:x, y:y};
    }
    // remove dups
    data_set.strokes = data_set.strokes.map(function(stroke) {
        return stroke.map(norm);
    });
}

function smooth(data_set) {
    data_set.strokes = data_set.strokes.map(function(stroke) {
        var nstroke = [];
        for (var i=0; i<stroke.length; i++) {
            var acc = { x:stroke[i].x * SMOOTH_ALPHA,
                        y:stroke[i].y * SMOOTH_ALPHA };
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
}

var canvas_id = 0;
function draw_letter(data_set, caption) {
    // data_set should be normalized (range [0,1], dups removed)
    var id = "c" + (canvas_id++);
    p("<canvas id="+JSON.stringify(id)+" title="+JSON.stringify(caption)+"></canvas>");
    p("<script type=\"text/javascript\">");
    p("(function() { ");
    p("  var canvas = document.getElementById("+JSON.stringify(id)+");");
    p("  canvas.width = canvas.height = "+CANVAS_RESOLUTION*RETINA_FACTOR+";");
    p("  var ctx = canvas.getContext(\"2d\");");
    var norm = function(pt) {
        return { x: pt.x*CANVAS_RESOLUTION*RETINA_FACTOR,
                 y: (1-pt.y)*CANVAS_RESOLUTION*RETINA_FACTOR };
    };
    // set ctx.stroke style, whatever that property is.
    data_set.strokes.forEach(function(stroke) {
        p("ctx.beginPath();");
        var start = norm(stroke[0]);
        p("ctx.moveTo("+start.x+","+start.y+");");
        for (var i=1; i<stroke.length; i++) {
            var pt = norm(stroke[i]);
            p("ctx.lineTo("+pt.x+","+pt.y+");");
        }
        p("ctx.stroke();");
    });
    // label data
    p("  ctx.fillStyle=\"#008\";");
    p("  ctx.font=\""+(10*RETINA_FACTOR)+"px sans-serif\";");
    p("  ctx.fillText("+JSON.stringify(data_set.source+" "+data_set.start)+", 0, 10, "+CANVAS_RESOLUTION*RETINA_FACTOR+");");
    p("})();");
    p("</script>");
}

// okay, draw the letters!
for (var i=0; i<data.set.length; i++) {
    normalize(data.set[i]);
    draw_letter(data.set[i], "Unipen");

    smooth(data.set[i]);
    draw_letter(data.set[i], "Smoothed");
}
