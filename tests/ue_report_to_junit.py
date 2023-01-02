import argparse
import json
import xml.etree.ElementTree as xmlTree
import xml.dom.minidom as miniDom

# unreal has test report in specific json format
# we need to convert that json to junit format to publish it in Jenkins

# junit docs: https://llg.cubic.org/docs/junit/
#             https://www.ibm.com/docs/en/developer-for-zos/14.1.0?topic=formats-junit-xml-format

# example of usage:
# ue_report_to_junit.py -ue_report_path=C:\Projects\TPS\Build\Tests\index.json -junit_xml_path=C:\Projects\TPS\Build\Tests\index.xml

def main():
    # parse args
    parser = argparse.ArgumentParser(description='Path to ue json report & path to output jUnit xml report')
    parser.add_argument('-ue_report_path', help='path to ue json report', required=True)
    parser.add_argument('-junit_xml_path', help='path to jUnit xml report', required=True)
    args = parser.parse_args()

    # load JSON
    json_file = open(args.ue_report_path, encoding="utf-8-sig")
    json_obj = json.loads(json_file.read())
    # print(json_obj)

    # create xml root
    xml_root = xmlTree.Element(
        "testsuites",
        name="Project Tests",
        tests=str(len(json_obj["tests"])),
        failures=str(json_obj["failed"]),
        time=str(json_obj["totalDuration"]),
        timestamp=json_obj["reportCreatedOn"],
    )

    # combine all UE tests
    tests = {}
    errors = {}
    for test in json_obj["tests"]:
        test_name = test["testDisplayName"]
        test_suite_name = test["fullTestPath"][: test["fullTestPath"].find(test_name) - 1]

        test_suite = tests[test_suite_name] if test_suite_name in tests else {}

        if test["errors"] == 0:
            test_suite.update({test_name: {}})
        else:
            error_msg = create_error_msg(test)
            error_count = 1 if test_suite_name not in errors else errors[test_suite_name] + 1
            errors.update({test_suite_name: error_count})
            test_suite.update({test_name: error_msg})

        tests.update({test_suite_name: test_suite})
    # print(tests)

    # convert to xml nodes
    for test_suite in tests:
        errs_number = errors[test_suite] if test_suite in errors else 0
        tests_count_in_suite=len(tests[test_suite])

        xml_test_suite = xmlTree.SubElement(
            xml_root,
            "testsuite",
            name=test_suite,
            tests=str(tests_count_in_suite),
            failures=str(errs_number),
            disabled="0",
        )

        for test_case in tests[test_suite]:
            xml_test_case = xmlTree.SubElement(xml_test_suite, "testcase", name=test_case, classname=test_suite)
            if tests[test_suite][test_case]:
                xmlTree.SubElement(xml_test_case, "failure", message=tests[test_suite][test_case])

    # write output XML
    xml_output = miniDom.parseString(xmlTree.tostring(xml_root, encoding="utf8", method="xml"))
    # print(xml_output.toprettyxml(indent="  "))

    xml_file = open(args.junit_xml_path, "w")
    xml_file.write(xml_output.toprettyxml(indent="  "))

def create_error_msg(test):
    error_msg = ""
    err_counter = 1
    for entry in test["entries"]:
        if entry["event"]["type"] == "Error":
            if error_msg != "":
                error_msg += " + "
            error_msg += "%s%s %s"%(str(err_counter), ":", entry["event"]["message"])
            err_counter += 1

    return error_msg

if __name__ == "__main__":
    main()