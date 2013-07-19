This tool can display statistics from log files to browser without any additional installation or programing.

User just need to make some simple changes to "cfg" file and run
     perl rtcharts.pl

and then point browser to "http://<IP>:8081"


Editing "cfg" file:
    To edit "cfg" file, one should have idea what log file(s) to use, how to grab statistics using regular expression.  
    Use the default "cfg" as an example.

    1. chart names are defined, first chart (0 based, we are engineers :-)) is "Name 111"
       second chart is "Name 222"
    2. each log file name should start from begining of line
    3. after each log file, there can be one or more curves/graphs. They are defined as
    4. <chartId> <curveId> <title of the curve> <regular expression to grab the statistics>


Caveats:
    Since this users "tail -f", so this tool only works on platforms that supports it, like Linux or Mac.
    Right now, we only support displaying two charts (each chart can have multiple curves/graphs). Will add support for more charts later.
