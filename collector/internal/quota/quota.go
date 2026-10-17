// Package quota intentionally has no credential or undocumented quota-file readers.
// Runtimes omit quota when no documented local usage source is available.
package quota

func Available() bool { return false }
