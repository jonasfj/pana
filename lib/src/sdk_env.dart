// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'logging.dart';
import 'utils.dart';

class DartSdk {
  final Map<String, String> _environment = {};
  String _dartCmd;
  String _dartAnalyzerCmd;
  String _dartfmtCmd;
  String _pubCmd;
  String _version;

  DartSdk({String sdkDir, Map<String, String> environment}) {
    String path = '';
    if (sdkDir != null) {
      path = sdkDir;
      if (!sdkDir.endsWith(Platform.pathSeparator)) {
        path += Platform.pathSeparator;
      }
    }

    if (environment != null) {
      _environment.addAll(environment);
    }
    _dartCmd = '${path}dart';
    _dartAnalyzerCmd = '${path}dartanalyzer';
    _dartfmtCmd = '${path}dartfmt';
    _pubCmd = '${path}pub';
  }

  String get version {
    if (_version == null) {
      var r = handleProcessErrors(
          Process.runSync(_dartCmd, ['--version'], environment: _environment));
      _version = r.stderr.toString().trim();
    }
    return _version;
  }

  Future<ProcessResult> runAnalyzer(String packageDir) {
    return Process.run(
      _dartAnalyzerCmd,
      ['--strong', '--format', 'machine', '.'],
      environment: _environment,
      workingDirectory: packageDir,
    );
  }

  Future<List<String>> filesNeedingFormat(String packageDir) async {
    var result = await Process.run(
      _dartfmtCmd,
      ['--dry-run', '--set-exit-if-changed', packageDir],
      environment: _environment,
    );
    if (result.exitCode == 0) {
      return const [];
    }

    var lines = LineSplitter.split(result.stdout).toList()..sort();
    assert(lines.isNotEmpty);
    return lines;
  }
}

class PubEnvironment {
  final DartSdk dartSdk;
  final String pubCacheDir;
  final Map<String, String> _environment = {};

  PubEnvironment({DartSdk dartSdk, this.pubCacheDir})
      : this.dartSdk = dartSdk ?? new DartSdk() {
    _environment.addAll(dartSdk._environment);
    if (!_environment.containsKey(_pubEnvironmentKey)) {
      // Then do the standard behavior. Extract the current value, if any,
      // and append the default value

      var pubEnvironment = <String>[];

      var currentEnv = Platform.environment[_pubEnvironmentKey];

      if (currentEnv != null) {
        pubEnvironment.addAll(currentEnv
                .split(
                    ':') // if there are many values, they should be separated by `:`
                .map((v) => v.trim()) // don't want whitespace
                .where((v) => v.isNotEmpty) // don't want empty values
            );
      }

      pubEnvironment.add('bot.pkg_pana');

      _environment[_pubEnvironmentKey] = pubEnvironment.join(':');
    }
    if (pubCacheDir != null) {
      var resolvedDir = new Directory(pubCacheDir).resolveSymbolicLinksSync();
      if (resolvedDir != pubCacheDir) {
        throw new ArgumentError([
          "Make sure you resolve symlinks:",
          pubCacheDir,
          resolvedDir
        ].join('\n'));
      }
      _environment['PUB_CACHE'] = pubCacheDir;
    }
  }

  Future<ProcessResult> runUpgrade(String packageDir, bool isFlutter,
      {int retryCount: 3}) async {
    ProcessResult result;

    var cmd = dartSdk._pubCmd;
    var args = <String>[];

    if (isFlutter) {
      //TODO(kevmoo) should we detect this and populate `sdk`?
      cmd = 'flutter';
      args.addAll(['packages', 'pub']);
    }

    args.addAll(['upgrade', '--verbosity', 'all']);

    do {
      retryCount--;

      log.info('Running `${ ([cmd]..addAll(args)).join(' ') }`...');

      result = await runProc(
        cmd,
        args,
        workingDirectory: packageDir,
        environment: _environment,
      );

      if (result.exitCode > 0 &&
          result.stderr
              .contains("Could not get versions for flutter from sdk")) {
        log.warning("Flutter SDK required!");
        retryCount = 0;
      }
    } while (result.exitCode > 0 && retryCount > 0);
    return result;
  }

  Future<PackageLocation> getLocation(String package, {String version}) async {
    var args = ['cache', 'add', '--verbose'];
    if (version != null) {
      args.addAll(['--version', version]);
    }
    args.add(package);

    var result = handleProcessErrors(await Process.run(
      dartSdk._pubCmd,
      args,
      environment: _environment,
    ));

    var match = _versionDownloadRexexp.allMatches(result.stdout.trim()).single;
    var pkgMatch = match[1];
    assert(pkgMatch == package);

    var versionString = match[2];
    assert(versionString.endsWith('.'));
    while (versionString.endsWith('.')) {
      versionString = versionString.substring(0, versionString.length - 1);
    }

    if (version != null) {
      assert(versionString == version);
    }

    // now get all installed packages
    result = handleProcessErrors(await Process.run(
      dartSdk._pubCmd,
      ['cache', 'list'],
      environment: _environment,
    ));

    var json = JSON.decode(result.stdout) as Map;

    var location =
        json['packages'][package][versionString]['location'] as String;

    if (location == null) {
      throw "Huh? This should be cached!";
    }

    return new PackageLocation(package, versionString, location);
  }
}

class PackageLocation {
  final String package;
  final String version;
  final String location;

  PackageLocation(this.package, this.version, this.location);
}

final _versionDownloadRexexp =
    new RegExp(r"^MSG : (?:Downloading |Already cached )([\w-]+) (.+)$");

const _pubEnvironmentKey = 'PUB_ENVIRONMENT';
