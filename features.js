define(['./point.js'], function(Point) {

    // tunable parameters
    var SMOOTH_N = 3, SMOOTH_ALPHA = .25;
    var RESAMPLE_INTERVAL = 1/7;//1/10;

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
        // remove length-1 strokes (too short)
        data_set.strokes = data_set.strokes.filter(function(stroke) {
            return stroke.length > 1;
        });
        if (data_set.strokes.length === 0) {
            return; // hmm.  bad data.
        }

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
        if (!dist) dist = RESAMPLE_INTERVAL;
        var stroke = data_set.strokes[0];
        if (stroke.length === 0) { return; /* bad data */ }
        var nstroke = [];
        var last = stroke[0];
        var d2next = 0;
        var wasPenUp=true;
        var first = true;
        stroke.forEach(function(pt) {
            var d = Point.dist(last, pt);

            while (d2next <= d) {
                var amt = (first)?0:(d2next/d);
                var npt = Point.interp(last, pt, amt);

                var segmentIsUp = pt.isUp;
                if (wasPenUp) { npt.isUp = true; }
                wasPenUp = first ? false : segmentIsUp;

                nstroke.push(npt);
                d2next += dist;
                first = false;
            }
            d2next -= d;
            last = pt;
        });
        if (nstroke[nstroke.length-1].isUp) {
            console.assert(!last.isUp, arguments[2]);
            nstroke.push(last);
        }
        /*
        // extrapolate last point an appropriate distance away
        if (d2next/dist > 0.5 && stroke.length > 1) {
        nstroke.push(last);
        var last2 = stroke[stroke.length-2];
        var namt = d2next / Point.dist(last2, last);
        if (namt < 5) {
        nstroke.push(Point.interp(last2, last, namt));
        }
        }
        */
        data_set.strokes = [ nstroke ];
    };

    var features = function(data_set) {
        var i;
        var points = data_set.strokes[0];
        var features = points.map(function() { return []; });
        for (i=0; i<points.length; i++) {
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
                // pen up!
                pt.isUp ? 1 : -1
            ];
        }
        // fill in curvature features
        for (i=0; i<features.length; i++) {
            var m1 = features[(i<1) ? 0 : (i-1)];
            var ft = features[i];
            var p1 = features[((i+1)<features.length)? (i+1) : (features.length-1)];

            var cosm1 = m1[2], sinm1 = m1[3];
            var cosp1 = p1[2], sinp1 = p1[3];
            ft[0] = (cosm1*cosp1) + (sinm1*sinp1);
            ft[1] = (cosm1*sinp1) - (sinm1*cosp1);
        }
        // rescale to normalize to (approximately) [-1,1]
        for (i=0; i<features.length; i++) {
            features[i][4] = (2 * features[i][4]) - 1;
            features[i][6] = (((features[i][6] + 1) / 3.2) * 2) - 1;
            features[i][7] = (features[i][7] * 50) - 1;
        }
        // save features
        data_set.features = features;
    };

    // exports
    return {
        // parameters
        SMOOTH_N: SMOOTH_N,
        SMOOTH_ALPHA: SMOOTH_ALPHA,
        RESAMPLE_INTERVAL: RESAMPLE_INTERVAL,
        // stroke processing functions
        normalize: normalize,
        smooth: smooth,
        singleStroke: singleStroke,
        equidist: equidist,
        features: features
    };
});
