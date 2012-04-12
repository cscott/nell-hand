define([], function() {
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
        if (a===b) return true;
        return (a.x === b.x) && (a.y === b.y) && (a.isUp === b.isUp);
    };
    Point.dist2 = function(a, b) {
        var dx = a.x - b.x, dy = a.y - b.y;
        return (dx*dx + dy*dy);
    };
    Point.dist = function(a, b) {
        return Math.sqrt(Point.dist2(a, b));
    };
    Point.interp = function(p1, p2, amt) {
        var x = p1.x + amt*(p2.x - p1.x);
        var y = p1.y + amt*(p2.y - p1.y);
        return new Point(x, y, p2.isUp);
    };

    return Point;
});