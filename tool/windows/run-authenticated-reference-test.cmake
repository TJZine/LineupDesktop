cmake_minimum_required(VERSION 3.14)

foreach(argument LINEUP_REFERENCE_CHECKER LINEUP_REFERENCE_HARNESS LINEUP_REFERENCE_DLL)
  if(NOT DEFINED ${argument} OR "${${argument}}" STREQUAL "")
    message(FATAL_ERROR "Authenticated-reference test requires ${argument}.")
  endif()
endforeach()

find_package(Python3 QUIET COMPONENTS Interpreter)
if(NOT Python3_Interpreter_FOUND)
  message(FATAL_ERROR
    "Authenticated-reference testing requires Python 3 on PATH. "
    "Production builds do not require Python.")
endif()

set(reference_arguments --harness "${LINEUP_REFERENCE_HARNESS}" --dll "${LINEUP_REFERENCE_DLL}")
if(DEFINED LINEUP_ALIGNMENT_OUTPUT)
  list(APPEND reference_arguments --output "${LINEUP_ALIGNMENT_OUTPUT}")
endif()
execute_process(
  COMMAND "${Python3_EXECUTABLE}" -B "${LINEUP_REFERENCE_CHECKER}" ${reference_arguments}
  RESULT_VARIABLE result)
if(NOT "${result}" STREQUAL "0")
  message(FATAL_ERROR "Authenticated-reference checker failed: ${result}")
endif()
