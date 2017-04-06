import 'package:path/path.dart' as p;
import 'package:quiver/core.dart';

class AnalyzerOutput implements Comparable<AnalyzerOutput> {
  static final _regexp = new RegExp('^' + // beginning of line
          '([\\w_\\.]+)\\|' * 3 + // first three error notes
          '([^\\|]+)\\|' + // file path
          '([\\w_\\.]+)\\|' * 3 + // line, column, length
          '(.*?)' + // rest is the error message
          '\$' // end of line
      );

  final String type;
  final String error;
  final String file;
  final int line;
  final int col;

  AnalyzerOutput(this.type, this.error, this.file, this.line, this.col);

  static AnalyzerOutput parse(String content, {String projectDir}) {
    if (content.isEmpty) {
      throw new ArgumentError('Provided content is empty.');
    }
    var matches = _regexp.allMatches(content).toList();

    if (matches.isEmpty) {
      throw new ArgumentError(
          'Provided content does not align with expectations.');
    }

    var match = matches.single;

    var type = [match[1], match[2], match[3]].join('|');

    var filePath = match[4];
    var line = match[5];
    var column = match[6];
    // length = 7
    var error = match[8];

    if (projectDir != null) {
      assert(p.isWithin(projectDir, filePath));
      filePath = p.relative(filePath, from: projectDir);
    }

    return new AnalyzerOutput(
        type, error, filePath, int.parse(line), int.parse(column));
  }

  factory AnalyzerOutput.fromJson(Map<String, dynamic> json) {
    var type = json['type'];
    var error = json['error'];
    var file = json['file'];
    var line = json['line'];
    var col = json['col'];
    return new AnalyzerOutput(type, error, file, line, col);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'file': file,
        'line': line,
        'col': col,
        'error': error,
      };

  @override
  int compareTo(AnalyzerOutput other) {
    var myVals = _values;
    var otherVals = other._values;
    for (var i = 0; i < myVals.length; i++) {
      var compare = (_values[i] as Comparable).compareTo(otherVals[i]);

      if (compare != 0) {
        return compare;
      }
    }

    assert(this == other);

    return 0;
  }

  @override
  int get hashCode => hashObjects(_values);

  @override
  bool operator ==(Object other) {
    if (other is AnalyzerOutput) {
      var myVals = _values;
      var otherVals = other._values;
      for (var i = 0; i < myVals.length; i++) {
        if (myVals[i] != otherVals[i]) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  List<Object> get _values => [file, line, col, type, error];
}
