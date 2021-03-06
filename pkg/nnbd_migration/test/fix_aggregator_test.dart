// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:nnbd_migration/src/decorated_type.dart';
import 'package:nnbd_migration/src/edit_plan.dart';
import 'package:nnbd_migration/src/fix_aggregator.dart';
import 'package:nnbd_migration/src/nullability_node.dart';
import 'package:nnbd_migration/src/nullability_node_target.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'abstract_single_unit.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FixAggregatorTest);
  });
}

@reflectiveTest
class FixAggregatorTest extends FixAggregatorTestBase {
  Future<void> test_addRequired() async {
    await analyze('f({int x}) => 0;');
    var previewInfo = run({
      findNode.defaultParameter('int x'): NodeChangeForDefaultFormalParameter()
        ..addRequiredKeyword = true
    });
    expect(previewInfo.applyTo(code), 'f({required int x}) => 0;');
  }

  Future<void> test_adjacentFixes() async {
    await analyze('f(a, b) => a + b;');
    var aRef = findNode.simple('a +');
    var bRef = findNode.simple('b;');
    var previewInfo = run({
      aRef: NodeChangeForExpression()..addNullCheck(_MockInfo()),
      bRef: NodeChangeForExpression()..addNullCheck(_MockInfo()),
      findNode.binary('a + b'): NodeChangeForExpression()
        ..addNullCheck(_MockInfo())
    });
    expect(previewInfo.applyTo(code), 'f(a, b) => (a! + b!)!;');
  }

  Future<void> test_eliminateDeadIf_changesInKeptCode() async {
    await analyze('''
f(int i, int/*?*/ j) {
  if (i != null) j.isEven;
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true,
      findNode.simple('j.isEven'): NodeChangeForExpression()
        ..addNullCheck(_MockInfo())
    });
    expect(previewInfo.applyTo(code), '''
f(int i, int/*?*/ j) {
  j!.isEven;
}
''');
  }

  Future<void> test_eliminateDeadIf_changesInKeptCode_expandBlock() async {
    await analyze('''
f(int i, int/*?*/ j) {
  if (i != null) {
    j.isEven;
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true,
      findNode.simple('j.isEven'): NodeChangeForExpression()
        ..addNullCheck(_MockInfo())
    });
    expect(previewInfo.applyTo(code), '''
f(int i, int/*?*/ j) {
  j!.isEven;
}
''');
  }

  Future<void> test_eliminateDeadIf_element_delete_drop_completely() async {
    await analyze('''
List<int> f(int i) {
  return [if (i == null) null];
}
''');
    var previewInfo = run({
      findNode.ifElement('=='): NodeChangeForIfElement()..conditionValue = false
    });
    expect(previewInfo.applyTo(code), '''
List<int> f(int i) {
  return [];
}
''');
  }

  Future<void>
      test_eliminateDeadIf_element_delete_drop_completely_not_in_sequence() async {
    await analyze('''
List<int> f(int i) {
  return [for (var x in [1, 2, 3]) if (i == null) null];
}
''');
    var previewInfo = run({
      findNode.ifElement('=='): NodeChangeForIfElement()..conditionValue = false
    });
    // This is a little kludgy; we could drop the `for` loop, but it's difficult
    // to do so, and this is a rare enough corner case that it doesn't seem
    // worth it.  Replacing the `if` with `...{}` has the right effect, since
    // it expands to nothing.
    expect(previewInfo.applyTo(code), '''
List<int> f(int i) {
  return [for (var x in [1, 2, 3]) ...{}];
}
''');
  }

  Future<void> test_eliminateDeadIf_element_delete_keep_else() async {
    await analyze('''
List<int> f(int i) {
  return [if (i == null) null else i + 1];
}
''');
    var previewInfo = run({
      findNode.ifElement('=='): NodeChangeForIfElement()..conditionValue = false
    });
    expect(previewInfo.applyTo(code), '''
List<int> f(int i) {
  return [i + 1];
}
''');
  }

  Future<void> test_eliminateDeadIf_element_delete_keep_then() async {
    await analyze('''
List<int> f(int i) {
  return [if (i == null) null else i + 1];
}
''');
    var previewInfo = run({
      findNode.ifElement('=='): NodeChangeForIfElement()..conditionValue = true
    });
    expect(previewInfo.applyTo(code), '''
List<int> f(int i) {
  return [null];
}
''');
  }

  Future<void> test_eliminateDeadIf_expression_delete_keep_else() async {
    await analyze('''
int f(int i) {
  return i == null ? null : i + 1;
}
''');
    var previewInfo = run({
      findNode.conditionalExpression('=='): NodeChangeForConditionalExpression()
        ..conditionValue = false
    });
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  return i + 1;
}
''');
  }

  Future<void> test_eliminateDeadIf_expression_delete_keep_then() async {
    await analyze('''
int f(int i) {
  return i == null ? null : i + 1;
}
''');
    var previewInfo = run({
      findNode.conditionalExpression('=='): NodeChangeForConditionalExpression()
        ..conditionValue = true
    });
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  return null;
}
''');
  }

  Future<void> test_eliminateDeadIf_statement_comment_keep_else() async {
    await analyze('''
int f(int i) {
  if (i == null) {
    return null;
  } else {
    return i + 1;
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = false
    }, removeViaComments: true);
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  /* if (i == null) {
    return null;
  } else {
    */ return i + 1; /*
  } */
}
''');
  }

  Future<void> test_eliminateDeadIf_statement_comment_keep_then() async {
    await analyze('''
int f(int i) {
  if (i == null) {
    return null;
  } else {
    return i + 1;
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true
    }, removeViaComments: true);
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  /* if (i == null) {
    */ return null; /*
  } else {
    return i + 1;
  } */
}
''');
  }

  Future<void>
      test_eliminateDeadIf_statement_delete_drop_completely_false() async {
    await analyze('''
void f(int i) {
  if (i == null) {
    print('null');
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = false
    });
    expect(previewInfo.applyTo(code), '''
void f(int i) {}
''');
  }

  Future<void>
      test_eliminateDeadIf_statement_delete_drop_completely_not_in_block() async {
    await analyze('''
void f(int i) {
  while (true)
    if (i == null) {
      print('null');
    }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = false
    });
    // Note: formatting is a little weird here but it's such a rare case that
    // we don't care.
    expect(previewInfo.applyTo(code), '''
void f(int i) {
  while (true)
    {}
}
''');
  }

  Future<void>
      test_eliminateDeadIf_statement_delete_drop_completely_true() async {
    await analyze('''
void f(int i) {
  if (i != null) {} else {
    print('null');
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true
    });
    expect(previewInfo.applyTo(code), '''
void f(int i) {}
''');
  }

  Future<void> test_eliminateDeadIf_statement_delete_keep_else() async {
    await analyze('''
int f(int i) {
  if (i == null) {
    return null;
  } else {
    return i + 1;
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = false
    });
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  return i + 1;
}
''');
  }

  Future<void> test_eliminateDeadIf_statement_delete_keep_then() async {
    await analyze('''
int f(int i) {
  if (i != null) {
    return i + 1;
  } else {
    return null;
  }
}
''');
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true
    });
    expect(previewInfo.applyTo(code), '''
int f(int i) {
  return i + 1;
}
''');
  }

  Future<void>
      test_eliminateDeadIf_statement_delete_keep_then_declaration() async {
    await analyze('''
void f(int i, String callback()) {
  if (i != null) {
    var i = callback();
  } else {
    return;
  }
  print(i);
}
''');
    // In this case we have to keep the block so that the scope of `var i`
    // doesn't widen.
    var previewInfo = run({
      findNode.statement('if'): NodeChangeForIfStatement()
        ..conditionValue = true
    });
    expect(previewInfo.applyTo(code), '''
void f(int i, String callback()) {
  {
    var i = callback();
  }
  print(i);
}
''');
  }

  Future<void> test_introduceAs_distant_parens_no_longer_needed() async {
    // Note: in principle it would be nice to delete the outer parens, but it's
    // difficult to see that they used to be necessary and aren't anymore, so we
    // leave them.
    await analyze('f(a, c) => a..b = (throw c..d);');
    var cd = findNode.cascade('c..d');
    var previewInfo =
        run({cd: NodeChangeForExpression()..introduceAs('int', _MockInfo())});
    expect(
        previewInfo.applyTo(code), 'f(a, c) => a..b = (throw (c..d) as int);');
  }

  Future<void> test_introduceAs_no_parens() async {
    await analyze('f(a, b) => a | b;');
    var expr = findNode.binary('a | b');
    var previewInfo =
        run({expr: NodeChangeForExpression()..introduceAs('int', _MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a, b) => a | b as int;');
  }

  Future<void> test_introduceAs_parens() async {
    await analyze('f(a, b) => a < b;');
    var expr = findNode.binary('a < b');
    var previewInfo = run(
        {expr: NodeChangeForExpression()..introduceAs('bool', _MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a, b) => (a < b) as bool;');
  }

  Future<void> test_keep_redundant_parens() async {
    await analyze('f(a, b, c) => a + (b * c);');
    var previewInfo = run({});
    expect(previewInfo, isEmpty);
  }

  Future<void> test_makeNullable() async {
    await analyze('f(int x) {}');
    var typeName = findNode.typeName('int');
    var previewInfo = run({
      typeName: NodeChangeForTypeAnnotation()
        ..makeNullable = true
        ..decoratedType = MockDecoratedType(
            MockDartType(toStringValueWithoutNullability: 'int'))
    });
    expect(previewInfo.applyTo(code), 'f(int? x) {}');
  }

  Future<void> test_noChangeToTypeAnnotation() async {
    await analyze('int x = 0;');
    var typeName = findNode.typeName('int');
    var previewInfo = run({
      typeName: NodeChangeForTypeAnnotation()
        ..decoratedType = MockDecoratedType(
            MockDartType(toStringValueWithoutNullability: 'int'))
    });
    expect(previewInfo.applyTo(code), 'int x = 0;');
    expect(previewInfo.applyTo(code, includeInformative: true), 'int  x = 0;');
    expect(previewInfo.values.single.single.info.description.appliedMessage,
        "Type 'int' was not made nullable");
  }

  Future<void> test_noInfoForTypeAnnotation() async {
    await analyze('int x = 0;');
    var typeName = findNode.typeName('int');
    var previewInfo = run({typeName: NodeChangeForTypeAnnotation()});
    expect(previewInfo, null);
  }

  Future<void> test_nullCheck_index_cascadeResult() async {
    await analyze('f(a) => a..[0].c;');
    var index = findNode.index('[0]');
    var previewInfo =
        run({index: NodeChangeForExpression()..addNullCheck(_MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a) => a..[0]!.c;');
  }

  Future<void> test_nullCheck_methodInvocation_cascadeResult() async {
    await analyze('f(a) => a..b().c;');
    var method = findNode.methodInvocation('b()');
    var previewInfo = run(
        {method: NodeChangeForMethodInvocation()..addNullCheck(_MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a) => a..b()!.c;');
  }

  Future<void> test_nullCheck_no_parens() async {
    await analyze('f(a) => a++;');
    var expr = findNode.postfix('a++');
    var previewInfo =
        run({expr: NodeChangeForExpression()..addNullCheck(_MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a) => a++!;');
  }

  Future<void> test_nullCheck_parens() async {
    await analyze('f(a) => -a;');
    var expr = findNode.prefix('-a');
    var previewInfo =
        run({expr: NodeChangeForExpression()..addNullCheck(_MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a) => (-a)!;');
  }

  Future<void> test_nullCheck_propertyAccess_cascadeResult() async {
    await analyze('f(a) => a..b.c;');
    var property = findNode.propertyAccess('b');
    var previewInfo = run(
        {property: NodeChangeForPropertyAccess()..addNullCheck(_MockInfo())});
    expect(previewInfo.applyTo(code), 'f(a) => a..b!.c;');
  }

  Future<void>
      test_removeAs_in_cascade_target_no_parens_needed_cascade() async {
    await analyze('f(a) => ((a..b) as dynamic)..c;');
    var cascade = findNode.cascade('a..b');
    var cast = cascade.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a) => a..b..c;');
  }

  Future<void>
      test_removeAs_in_cascade_target_no_parens_needed_conditional() async {
    // TODO(paulberry): would it be better to keep the parens in this case for
    // clarity, even though they're not needed?
    await analyze('f(a, b, c) => ((a ? b : c) as dynamic)..d;');
    var conditional = findNode.conditionalExpression('a ? b : c');
    var cast = conditional.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => a ? b : c..d;');
  }

  Future<void>
      test_removeAs_in_cascade_target_parens_needed_assignment() async {
    await analyze('f(a, b) => ((a = b) as dynamic)..c;');
    var assignment = findNode.assignment('a = b');
    var cast = assignment.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b) => (a = b)..c;');
  }

  Future<void> test_removeAs_in_cascade_target_parens_needed_throw() async {
    await analyze('f(a) => ((throw a) as dynamic)..b;');
    var throw_ = findNode.throw_('throw a');
    var cast = throw_.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a) => (throw a)..b;');
  }

  Future<void>
      test_removeAs_lower_precedence_do_not_remove_inner_parens() async {
    await analyze('f(a, b, c) => (a == b) as Null == c;');
    var expr = findNode.binary('a == b');
    var previewInfo =
        run({expr.parent.parent: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => (a == b) == c;');
  }

  Future<void> test_removeAs_lower_precedence_remove_inner_parens() async {
    await analyze('f(a, b) => (a == b) as Null;');
    var expr = findNode.binary('a == b');
    var previewInfo =
        run({expr.parent.parent: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b) => a == b;');
  }

  Future<void> test_removeAs_parens_needed_due_to_cascade() async {
    // Note: parens are needed, and they could either be around `c..d` or around
    // `throw c..d`.  In an ideal world, we would see that we can just keep the
    // parens we have, but this is difficult because we don't see that the
    // parens are needed until we walk far enough up the AST to see that we're
    // inside a casade expression.  So we drop the parens and then create new
    // ones surrounding `throw c..d`.
    //
    // Strictly speaking the code we produce is correct, it's just making a
    // slightly larger edit than necessary.  This is presumably a really rare
    // corner case so for now we're not worrying about it.
    await analyze('f(a, c) => a..b = throw (c..d) as int;');
    var cd = findNode.cascade('c..d');
    var cast = cd.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, c) => a..b = (throw c..d);');
  }

  Future<void>
      test_removeAs_parens_needed_due_to_cascade_in_conditional_else() async {
    await analyze('f(a, b, c) => a ? b : (c..d) as int;');
    var cd = findNode.cascade('c..d');
    var cast = cd.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => a ? b : (c..d);');
  }

  Future<void>
      test_removeAs_parens_needed_due_to_cascade_in_conditional_then() async {
    await analyze('f(a, b, d) => a ? (b..c) as int : d;');
    var bc = findNode.cascade('b..c');
    var cast = bc.parent.parent;
    var previewInfo = run({cast: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, d) => a ? (b..c) : d;');
  }

  Future<void> test_removeAs_raise_precedence_do_not_remove_parens() async {
    await analyze('f(a, b, c) => a | (b | c as int);');
    var expr = findNode.binary('b | c');
    var previewInfo =
        run({expr.parent: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => a | (b | c);');
  }

  Future<void> test_removeAs_raise_precedence_no_parens_to_remove() async {
    await analyze('f(a, b, c) => a = b | c as int;');
    var expr = findNode.binary('b | c');
    var previewInfo =
        run({expr.parent: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => a = b | c;');
  }

  Future<void> test_removeAs_raise_precedence_remove_parens() async {
    await analyze('f(a, b, c) => a < (b | c as int);');
    var expr = findNode.binary('b | c');
    var previewInfo =
        run({expr.parent: NodeChangeForAsExpression()..removeAs = true});
    expect(previewInfo.applyTo(code), 'f(a, b, c) => a < b | c;');
  }

  Future<void> test_removeNullAwarenessFromMethodInvocation() async {
    await analyze('f(x) => x?.m();');
    var methodInvocation = findNode.methodInvocation('?.');
    var previewInfo = run({
      methodInvocation: NodeChangeForMethodInvocation()
        ..removeNullAwareness = true
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.m();');
  }

  Future<void>
      test_removeNullAwarenessFromMethodInvocation_changeArgument() async {
    await analyze('f(x) => x?.m(x);');
    var methodInvocation = findNode.methodInvocation('?.');
    var argument = findNode.simple('x);');
    var previewInfo = run({
      methodInvocation: NodeChangeForMethodInvocation()
        ..removeNullAwareness = true,
      argument: NodeChangeForExpression()..addNullCheck(_MockInfo())
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.m(x!);');
  }

  Future<void>
      test_removeNullAwarenessFromMethodInvocation_changeTarget() async {
    await analyze('f(x) => (x as dynamic)?.m();');
    var methodInvocation = findNode.methodInvocation('?.');
    var cast = findNode.as_('as');
    var previewInfo = run({
      methodInvocation: NodeChangeForMethodInvocation()
        ..removeNullAwareness = true,
      cast: NodeChangeForAsExpression()..removeAs = true
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.m();');
  }

  Future<void>
      test_removeNullAwarenessFromMethodInvocation_changeTypeArgument() async {
    await analyze('f(x) => x?.m<int>();');
    var methodInvocation = findNode.methodInvocation('?.');
    var typeAnnotation = findNode.typeAnnotation('int');
    var previewInfo = run({
      methodInvocation: NodeChangeForMethodInvocation()
        ..removeNullAwareness = true,
      typeAnnotation: NodeChangeForTypeAnnotation()
        ..makeNullable = true
        ..decoratedType = MockDecoratedType(
            MockDartType(toStringValueWithoutNullability: 'int'))
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.m<int?>();');
  }

  Future<void> test_removeNullAwarenessFromPropertyAccess() async {
    await analyze('f(x) => x?.y;');
    var propertyAccess = findNode.propertyAccess('?.');
    var previewInfo = run({
      propertyAccess: NodeChangeForPropertyAccess()..removeNullAwareness = true
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.y;');
  }

  Future<void> test_removeNullAwarenessFromPropertyAccess_changeTarget() async {
    await analyze('f(x) => (x as dynamic)?.y;');
    var propertyAccess = findNode.propertyAccess('?.');
    var cast = findNode.as_('as');
    var previewInfo = run({
      propertyAccess: NodeChangeForPropertyAccess()..removeNullAwareness = true,
      cast: NodeChangeForAsExpression()..removeAs = true
    });
    expect(previewInfo.applyTo(code), 'f(x) => x.y;');
  }

  Future<void> test_requiredAnnotationToRequiredKeyword_prefixed() async {
    addMetaPackage();
    await analyze('''
import 'package:meta/meta.dart' as meta;
f({@meta.required int x}) {}
''');
    var annotation = findNode.annotation('required');
    var previewInfo = run({
      annotation: NodeChangeForAnnotation()..changeToRequiredKeyword = true
    });
    expect(previewInfo.applyTo(code), '''
import 'package:meta/meta.dart' as meta;
f({required int x}) {}
''');
    expect(previewInfo.values.single.single.isDeletion, true);
  }

  Future<void> test_requiredAnnotationToRequiredKeyword_renamed() async {
    addMetaPackage();
    await analyze('''
import 'package:meta/meta.dart';
const foo = required;
f({@foo int x}) {}
''');
    var annotation = findNode.annotation('@foo');
    var previewInfo = run({
      annotation: NodeChangeForAnnotation()..changeToRequiredKeyword = true
    });
    expect(previewInfo.applyTo(code), '''
import 'package:meta/meta.dart';
const foo = required;
f({required int x}) {}
''');
  }

  Future<void> test_requiredAnnotationToRequiredKeyword_simple() async {
    addMetaPackage();
    await analyze('''
import 'package:meta/meta.dart';
f({@required int x}) {}
''');
    var annotation = findNode.annotation('required');
    var previewInfo = run({
      annotation: NodeChangeForAnnotation()..changeToRequiredKeyword = true
    });
    expect(previewInfo.applyTo(code), '''
import 'package:meta/meta.dart';
f({required int x}) {}
''');
    expect(previewInfo.values.single.single.isDeletion, true);
  }

  Future<void> test_variableDeclarationList_addExplicitType_insert() async {
    await analyze('final x = 0;');
    var previewInfo = run({
      findNode.variableDeclarationList('final'):
          NodeChangeForVariableDeclarationList()
            ..addExplicitType =
                MockDartType(toStringValueWithNullability: 'int')
    });
    expect(previewInfo.applyTo(code), 'final int x = 0;');
  }

  Future<void> test_variableDeclarationList_addExplicitType_no() async {
    await analyze('var x = 0;');
    var previewInfo = run({
      findNode.variableDeclarationList('var'):
          NodeChangeForVariableDeclarationList()
    });
    expect(previewInfo, isNull);
  }

  Future<void> test_variableDeclarationList_addExplicitType_otherPlans() async {
    await analyze('var x = 0;');
    var previewInfo = run({
      findNode.variableDeclarationList('var'):
          NodeChangeForVariableDeclarationList()
            ..addExplicitType =
                MockDartType(toStringValueWithNullability: 'int'),
      findNode.integerLiteral('0'): NodeChangeForExpression()
        ..addNullCheck(_MockInfo())
    });
    expect(previewInfo.applyTo(code), 'int x = 0!;');
  }

  Future<void> test_variableDeclarationList_addExplicitType_replaceVar() async {
    await analyze('var x = 0;');
    var previewInfo = run({
      findNode.variableDeclarationList('var'):
          NodeChangeForVariableDeclarationList()
            ..addExplicitType =
                MockDartType(toStringValueWithNullability: 'int')
    });
    expect(previewInfo.applyTo(code), 'int x = 0;');
  }
}

class FixAggregatorTestBase extends AbstractSingleUnitTest {
  String code;

  Future<void> analyze(String code) async {
    this.code = code;
    await resolveTestUnit(code);
  }

  Map<int, List<AtomicEdit>> run(Map<AstNode, NodeChange> changes,
      {bool removeViaComments: false}) {
    return FixAggregator.run(testUnit, testCode, changes,
        removeViaComments: removeViaComments);
  }
}

class MockDartType implements TypeImpl {
  final String toStringValueWithNullability;

  final String toStringValueWithoutNullability;

  const MockDartType(
      {this.toStringValueWithNullability,
      this.toStringValueWithoutNullability});

  @override
  String getDisplayString({
    bool skipAllDynamicArguments = false,
    bool withNullability = false,
  }) {
    var result = withNullability
        ? toStringValueWithNullability
        : toStringValueWithoutNullability;
    expect(result, isNotNull);
    return result;
  }

  @override
  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class MockDecoratedType implements DecoratedType {
  @override
  final DartType type;

  const MockDecoratedType(this.type);

  @override
  NullabilityNode get node =>
      NullabilityNode.forTypeAnnotation(NullabilityNodeTarget.text('test'));

  @override
  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _MockInfo implements AtomicEditInfo {
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
