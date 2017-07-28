// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pana.license;

import 'dart:async';
import 'dart:io';

import 'package:json_serializable/annotations.dart';
import 'package:path/path.dart' as p;

part 'license.g.dart';

@JsonSerializable()
class License extends Object with _$LicenseSerializerMixin {
  final String name;
  @JsonKey(includeIfNull: false)
  final String version;

  License(this.name, [this.version]);

  factory License.fromJson(Map<String, dynamic> json) =>
      _$LicenseFromJson(json);

  @override
  String toString() {
    if (version == null) return name;
    return '$name $version';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is License &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          version == other.version;

  @override
  int get hashCode => name.hashCode ^ version.hashCode;
}

abstract class LicenseNames {
  static const String AGPL = 'AGPL';
  static const String BSD = 'BSD';
  static const String GPL = 'GPL';
  static const String MIT = 'MIT';
  static const String missing = 'missing';
  static const String unknown = 'unknown';
}

Future<License> detectLicenseInDir(String baseDir) async {
  var list = await new Directory(baseDir).list().toList();
  final File licenseFile = list.firstWhere(_isLicenseFile, orElse: () => null);
  if (licenseFile == null) {
    return new License(LicenseNames.missing);
  }
  var content = await licenseFile.readAsString();
  var license = detectLicenseInContent(content);
  return license ?? new License(LicenseNames.unknown);
}

License detectLicenseInContent(String content) {
  var stripped = _longTextPrepare(content);

  String version;
  var versionMatch = _version.firstMatch(stripped);
  if (versionMatch != null) {
    version = versionMatch.group(1);
    if (version.isNotEmpty && !version.contains('.')) {
      version += '.0';
    }
  }

  if (_agpl.hasMatch(stripped)) {
    return new License(LicenseNames.AGPL, version);
  }
  if (_gplLong.hasMatch(stripped)) {
    return new License(LicenseNames.GPL, version);
  }
  if (_gplShort.hasMatch(stripped)) {
    return new License(LicenseNames.GPL, version);
  }
  if (_mit.hasMatch(stripped)) {
    return new License(LicenseNames.MIT, version);
  }

  if (_bsdPreamble.hasMatch(stripped) && _bsdEmphasis.hasMatch(stripped)) {
    return new License(LicenseNames.BSD);
  }

  return null;
}

final RegExp _whitespace = new RegExp('\\s+');
final RegExp _extraCharacters = new RegExp('\\"|\\\'|\\*');

final RegExp _agpl =
    new RegExp('GNU AFFERO GENERAL PUBLIC LICENSE', caseSensitive: false);
final RegExp _gplLong =
    new RegExp('GENERAL PUBLIC LICENSE', caseSensitive: false);
final RegExp _gplShort = new RegExp('GNU GPL', caseSensitive: false);
final RegExp _mit = new RegExp('The MIT License', caseSensitive: false);
final RegExp _version =
    new RegExp(r'Version (\d+(\.\d*)?)', caseSensitive: false);

final RegExp _bsdPreamble = _longTextRegExp('''
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met''');

final RegExp _bsdEmphasis = _longTextRegExp('''
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED.
''');

bool _isLicenseFile(FileSystemEntity fse) {
  if (fse is File) {
    var relative = p.relative(fse.path, from: fse.parent.path);
    var lower = relative.toLowerCase();
    return lower == 'license' ||
        lower == 'license.txt' ||
        lower == 'license.md';
  }
  return false;
}

String _longTextPrepare(String text) =>
    text.replaceAll(_extraCharacters, ' ').replaceAll(_whitespace, ' ').trim();

RegExp _longTextRegExp(String text) =>
    new RegExp(_longTextPrepare(text), caseSensitive: false);