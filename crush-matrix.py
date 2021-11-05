#!/usr/bin/python2.7

"""Turns a coverage/kill-matrix into a statement/mutant suspiciousness vector. Usage:

    crush-matrix \
      --formula (tarantula|ochiai|dstar2|barinel|opt2|muse|jaccard) \
      --matrix FILE \
      --element-type (Statement|Mutant) \
      --element-names FILE \
      --total-defn (tests|mutants) \
      [--hybrid-scheme (numerator|constant|mirror|coverage-only) \
       --hybrid-coverage-matrix FILE] \
      --output FILE

where `--element-type` indicates whether the entries of the resulting vector correspond to statements or mutants;

and `--element-names` is the path to a file whose nth line identifies the code element (statement/mutant) to which the nth matrix column refers

and `--total-defn` indicates whether, in the formula, "totalpassed" should refer to the number of passing tests, or the number of times a passing test covers/kills an element. (And the same for "totalfailed".)

`--hybrid-scheme` and `--hybrid-coverage-matrix` should come together or not at all. They should be present iff the FLT being performed belonged to the "hybrid" family; in this case,

    * `--matrix` indicates the *mutant kill-matrix* (telling which tests kill which mutants),
    * `--hybrid-coverage-matrix` indicates the *mutant coverage-matrix* (telling which tests cover which mutants), and
    * `--hybrid-scheme` indicates how the two matrices are combined: if `numerator`, mutants covered by failing tests will have some small/moderate increase in suspiciousness (usually by incrementing the numerator of some fraction by 1); if `constant`, mutants covered by failing tests will have some large increase in suspiciousness (incrementing the whole suspiciousness by 1); if `mirror`, each mutant's suspiciousness will be the sum of (the formula applied to its column in the kill-matrix) and (the formula applied to its column in the coverage-matrix); if  `coverage-only`, the formula will *only* be applied to its column in the coverage-matrix, and the kill-matrix will be ignored.

"""

from __future__ import division
import collections
import re
import sys
import traceback

from formulas import *

def crush_row(formula, hybrid_scheme, passed, failed, totalpassed, totalfailed, passed_covered=None, failed_covered=None, totalpassed_covered=0.0, totalfailed_covered=0.0):
  '''Returns the suspiciousness of a statement or mutant.

  ``formula`` (a string) is the name of the formula to plug passed/failed/totalpassed/totalfailed into.

  ``hybrid_scheme`` ("numerator", "constant", or "mirror"), useful for MBFL only, specifies how the formula should be modified to incorporate the number of passing/failing tests that *cover* the mutant (rather than kill it).
  '''
  try:
    if hybrid_scheme is None:
      return FORMULAS[formula](passed, failed, totalpassed, totalfailed)
    elif hybrid_scheme == 'numerator':
      return HYBRID_NUMERATOR_FORMULAS[formula](passed, failed, totalpassed, totalfailed, failed_covered > 0)
    elif hybrid_scheme == 'constant':
      return FORMULAS[formula](passed, failed, totalpassed, totalfailed) + (1 if failed_covered > 0 else 0)
    elif hybrid_scheme == 'mirror':
      return (FORMULAS[formula](passed, failed, totalpassed, totalfailed) +
              FORMULAS[formula](passed_covered, failed_covered, totalpassed_covered, totalfailed_covered))/2.
    elif hybrid_scheme == 'coverage-only':
      return FORMULAS[formula](passed_covered, failed_covered, totalpassed_covered, totalfailed_covered)
    raise ValueError('unrecognized hybrid scheme name: {!r}'.format(hybrid_scheme))
  except ZeroDivisionError as zeroDivisionError:
    sys.stderr.write("Warn: catch integer division or modulo by zero for " + formula + "\n")
    sys.stderr.write("Passed: " + str(passed) + "\nFailed: " + str(failed) + "\nTotalPassed: " + str(totalpassed) + "\nTotalFailed: " + str(totalfailed) + "\n")
    return 0
  except:
    traceback.print_exc()
    sys.stderr.write("Passed: " + str(passed) + "\nFailed: " + str(failed) + "\nTotalPassed: " + str(totalpassed) + "\nTotalFailed: " + str(totalfailed) + "\n")
    sys.exit(1)

def suspiciousnesses_from_tallies(formula, hybrid_scheme, tally, hybrid_coverage_tally):
  '''Returns a dict mapping element-number to suspiciousness.
  '''
  if hybrid_coverage_tally is None:
    passed_covered = failed_covered = collections.defaultdict(lambda: None)
    totalpassed_covered = totalfailed_covered = 0
  else:
    passed_covered = hybrid_coverage_tally.passed
    failed_covered = hybrid_coverage_tally.failed
    totalpassed_covered = hybrid_coverage_tally.totalpassed
    totalfailed_covered = hybrid_coverage_tally.totalfailed

  return {
    element: crush_row(
      formula=formula, hybrid_scheme=hybrid_scheme,
      passed=float(tally.passed[element]), failed=float(tally.failed[element]),
      totalpassed=float(tally.totalpassed), totalfailed=float(tally.totalfailed),
      passed_covered=passed_covered[element], failed_covered=failed_covered[element],
      totalpassed_covered=float(totalpassed_covered), totalfailed_covered=float(totalfailed_covered))
    for element in range(tally.n_elements)}


TestSummary = collections.namedtuple('TestSummary', ('triggering', 'covered_elements'))
def parse_test_summary(line, n_elements):
  words = line.strip().split(' ')
  coverages, sign = words[:-1], words[-1]
  if len(coverages) != n_elements:
    raise ValueError("expected {expected} elements in each row, got {actual} in {line!r}".format(expected=n_elements, actual=len(coverages), line=line))
  return TestSummary(
    triggering=(sign == '-'),
    covered_elements=set(i for i in range(len(words)) if words[i]=='1'))

PassFailTally = collections.namedtuple('PassFailTally', ('n_elements', 'passed', 'failed', 'totalpassed', 'totalfailed'))
def tally_matrix(matrix_file, total_defn, n_elements):
  '''Returns a PassFailTally describing how many passing/failing tests there are, and how many of each cover each code element.

  ``total_defn`` may be "tests" (in which case the tally's ``totalpassed`` will be the number of passing tests) or "elements" (in which case it'll be the number of times a passing test covers a code element) (and same for ``totalfailed``).

  ``n_elements`` is the number of code elements that each row of the matrix should indicate coverage for.
  '''
  summaries = (parse_test_summary(line, n_elements) for line in matrix_file)

  passed = {i: 0 for i in range(n_elements)}
  failed = {i: 0 for i in range(n_elements)}
  totalpassed = 0
  totalfailed = 0
  for summary in summaries:
    if summary.triggering:
      totalfailed += (1 if total_defn == 'tests' else len(summary.covered_elements))
      for element_number in summary.covered_elements:
        failed[element_number] += 1
    else:
      totalpassed += (1 if total_defn == 'tests' else len(summary.covered_elements))
      for element_number in summary.covered_elements:
        passed[element_number] += 1

  return PassFailTally(n_elements, passed, failed, totalpassed, totalfailed)

if __name__ == '__main__':

  import argparse
  import csv

  parser = argparse.ArgumentParser()
  parser.add_argument('--formula', required=True, choices=set(FORMULAS.keys()))
  parser.add_argument('--matrix', required=True, help='path to the coverage/kill-matrix')
  parser.add_argument('--hybrid-scheme', choices=['numerator', 'constant', 'mirror', 'coverage-only'])
  parser.add_argument('--hybrid-coverage-matrix', help='optional coverage matrix for hybrid techniques')
  parser.add_argument('--element-type', required=True, choices=['Statement', 'Mutant'], help='file enumerating names for matrix columns')
  parser.add_argument('--element-names', required=True, help='file enumerating names for matrix columns')
  parser.add_argument('--total-defn', required=True, choices=['tests', 'elements'], help='whether totalpassed/totalfailed should counts tests or covered/killed elements')
  parser.add_argument('--output', required=True, help='file to write suspiciousness vector to')

  args = parser.parse_args()

  if (args.hybrid_scheme is None) != (args.hybrid_coverage_matrix is None):
    raise RuntimeError('--hybrid-scheme and --hybrid-coverage-matrix should come together or not at all')

  with open(args.element_names) as name_file:
    next(name_file)
    element_names = {i: name.strip() for i, name in enumerate(name_file)}

  n_elements = len(element_names)

  with open(args.matrix) as matrix_file:
    tally = tally_matrix(matrix_file, args.total_defn, n_elements=n_elements)

  if args.hybrid_scheme is None:
    hybrid_coverage_tally = None
  else:
    with open(args.hybrid_coverage_matrix) as coverage_matrix_file:
      hybrid_coverage_tally = tally_matrix(coverage_matrix_file, args.total_defn, n_elements)


  suspiciousnesses = suspiciousnesses_from_tallies(
    formula=args.formula, hybrid_scheme=args.hybrid_scheme,
    tally=tally, hybrid_coverage_tally=hybrid_coverage_tally)

  with open(args.output, 'w') as output_file:
    writer = csv.DictWriter(output_file, [args.element_type,'Suspiciousness'])
    writer.writeheader()
    for element in range(n_elements):
      writer.writerow({
        args.element_type: element_names[element],
        'Suspiciousness': suspiciousnesses[element]})
