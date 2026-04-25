import 'dart:convert';

/// Exit code for successful CLI execution.
const successExitCode = 0;

/// Exit code for command-line usage errors.
const usageExitCode = 64;

/// Exit code for unexpected software failures.
const softwareExitCode = 70;

/// Default number of representative paths to include for method inspection.
const defaultMethodPathLimit = 3;

/// Shared JSON encoder for CLI output.
const jsonEncoder = JsonEncoder.withIndent('  ');

/// Appends a stable examples section to a formatted command usage string.
String usageWithExamples(String usage, List<String> examples) {
  final buffer = StringBuffer(usage.trimRight())
    ..writeln()
    ..writeln()
    ..writeln('Examples:');
  for (final example in examples) {
    buffer.writeln('  $example');
  }
  return buffer.toString().trimRight();
}
