#!/bin/bash


syntax_error_program () {
  name="../bad/syntax_errors/program$1"
}

type_error_program () {
  name="../bad/type_errors/program$1"
}

runtime_program () {
  name="../bad/runtime/program$1"
}



cd src
make > /dev/null
touch obtained_output.txt

echo "syntax errors:" > obtained_output.txt
for i in {1..8}
do
  syntax_error_program $i
  echo -n "program$i: " >> obtained_output.txt
  ./interpreter < $name 2>> obtained_output.txt
done

echo "type errors:" >> obtained_output.txt
for i in {1..16}
do
  type_error_program $i
  echo -n "program$i: " >> obtained_output.txt
  ./interpreter < $name 2>> obtained_output.txt
done

echo "runtime:" >> obtained_output.txt
for i in {1..1}
do
  runtime_program $i
  echo -n "program$i: " >> obtained_output.txt
  ./interpreter < $name 2>> obtained_output.txt
done

echo "correct:" >> obtained_output.txt
echo -n "simple: " >> obtained_output.txt
./interpreter < "../good/simple" >> obtained_output.txt
echo -n "exceptions_static_binding: " >> obtained_output.txt
./interpreter < "../good/exceptions_static_binding" >> obtained_output.txt
echo -n "const: " >> obtained_output.txt
./interpreter < "../good/const" >> obtained_output.txt
echo -n "recursion: " >> obtained_output.txt
./interpreter < "../good/recursion" >> obtained_output.txt
echo -n "exception_shadowing_break: " >> obtained_output.txt
./interpreter < "../good/exception_shadowing_break" >> obtained_output.txt
echo -n "ref_passing: " >> obtained_output.txt
./interpreter < "../good/ref_passing" >> obtained_output.txt
echo -n "arth_operations: " >> obtained_output.txt
./interpreter < "../good/arth_operations" >> obtained_output.txt
echo -n "relation_operations: " >> obtained_output.txt
./interpreter < "../good/relation_operations" >> obtained_output.txt

diff obtained_output.txt ../expected_output.txt

rm obtained_output.txt
make clean >/dev/null
rm interpreter
cd ..
