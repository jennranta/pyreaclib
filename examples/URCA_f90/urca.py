# C-burning with A=23 URCA rate module generator

from pyreaclib.networks import SundialsNetwork

files = ["c12-c12a-ne20-cf88",
         "c12-c12n-mg23-cf88",
         "c12-c12p-na23-cf88",
         "na23--ne23-toki",
         "ne23--na23-toki",
         "n--p-wc12"]

urca_net = SundialsNetwork(files, use_cse=True)
urca_net.write_network()





