#!/usr/bin/node
// running with node 0.7.5, installed 'commander' and 'progress'

var CANVAS_RESOLUTION = 100;
var RETINA_FACTOR = 1;

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

var canvas_id = 0;
function draw_letter(data_set) {
    var id = "c" + (canvas_id++);
    p("<canvas id=\""+id+"\"></canvas>");
    p("<script type=\"text/javascript\">");
    p("(function() { ");
    p("  var canvas = document.getElementById(\""+id+"\");");
    p("  canvas.width = canvas.height = "+CANVAS_RESOLUTION*RETINA_FACTOR+";");
    p("  var ctx = canvas.getContext(\"2d\");");
    // find bounding box
    var min_x, min_y, max_x, max_y; var first=true;
    // Ugh: this should be a one-liner...
    data_set.strokes.forEach(function(stroke) {
        stroke.forEach(function(point) {
            if (first) {
                min_x = max_x = point[0];
                min_y = max_y = point[1];
                first = false;
            } else {
                min_x = Math.min(min_x, point[0]);
                max_x = Math.max(max_x, point[0]);
                min_y = Math.min(min_y, point[1]);
                max_y = Math.max(max_y, point[1]);
            }
        });
    });
    // use correct aspect ratio
    var x_size = (max_x - min_x), y_size = (max_y - min_y);
    var size = Math.max(x_size, y_size);
    function norm(x, y) {
        x = CANVAS_RESOLUTION * RETINA_FACTOR * (x - min_x) / size;
        y = CANVAS_RESOLUTION * RETINA_FACTOR * (y - min_y) / size;
        // flip on the y axis
        y = (CANVAS_RESOLUTION * RETINA_FACTOR) - y;
        return {x:x, y:y};
    }
    p("// bb: "+min_x+","+min_y+"-"+max_x+","+max_y);
    // set ctx.stroke style, whatever that property is.
    data_set.strokes.forEach(function(stroke) {
        p("ctx.beginPath();");
        var start = norm(stroke[0][0], stroke[0][1]);
        p("ctx.moveTo("+start.x+","+start.y+");");
        for (var i=1; i<stroke.length; i++) {
            if (stroke[i][0] == stroke[i-1][0] &&
                stroke[i][1] == stroke[i-1][1]) continue; // skip repeated pts.
            var pt = norm(stroke[i][0], stroke[i][1]);
            p("ctx.lineTo("+pt.x+","+pt.y+");");
        }
        p("ctx.stroke();");
    });
    // label data
    p("  ctx.fillStyle=\"#008\";");
    p("  ctx.fillText("+JSON.stringify(data_set.source+" "+data_set.start)+", 0, 10, "+CANVAS_RESOLUTION*RETINA_FACTOR+");");
    p("})();");
    p("</script>");
}

// okay, draw the letters!
for (var i=0; i<data.set.length; i++) {
    draw_letter(data.set[i]);
}
