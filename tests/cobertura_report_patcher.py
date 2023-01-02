import argparse
import xml.etree.ElementTree as ET

# problem: Cobertura report from OpenCppCoverage has a compatibility problem with Jenkin's Cobertura plugin
# without forward slashes in the source node after the disc name plugin won't display the source code in Jenkins

# script updates <source>C:</source> -> <source>C:\\</source>

# example of usage:
# cobertura_report_patcher.py -cobertura_report_path=c:\JenkinsJobs\TPSGameTests\Build\Tests\CodeCoverageReport.xml

def main():
    # parse args
    parser = argparse.ArgumentParser(description='Path to cobertura xml report')
    parser.add_argument('-cobertura_report_path', help='path to cobertura xml report', required=True)
    args = parser.parse_args()

    # load XML
    xml_tree = ET.parse(args.cobertura_report_path)
    xml_root = xml_tree.getroot()

    # patch source XML node
    xml_node_source = xml_root[0].find('source')
    xml_node_source.text = xml_node_source.text + "\\\\"
    
    # write XML back
    xml_tree.write(args.cobertura_report_path)

if __name__ == "__main__":
    main()