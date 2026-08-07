import argparse
import csv
import os


def read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct):
    total_bits = 0
    total_packets = 0
    duration = 0
    start_time = None
    end_time = None

    with open(file, "r") as trace_file:
        for line in trace_file:
            op = line.split()[0]
            if "+" == op or "r" == op:
                time = float(line.split()[1]) 
                size = int(line.split()[26])
                total_bits += size * 8  # Convert bytes to bits
                total_packets += 1
                if start_time is None:
                    start_time = time

                end_time = time
                duration = end_time - start_time

    if duration == 0:
        bandwidth_bps = 0
        packets_ps = 0
    else:
        bandwidth_bps = (total_bits) / duration  # Convert bytes to bits and divide by time
        packets_ps = total_packets / duration  # packets per second

    bandwidth_mbps = bandwidth_bps / 1e6          # Convert bps to Mbps
    print(f"{path}: {hop}: Total bits: {total_bits}, Duration: {duration} seconds, Data Rate: {bandwidth_bps} bps")
    
    
    writer.writerow({
                    'simulation_time': args.simulationTime,
                    'extra_router': args.numExtraRouters,
                    'extra_detour': args.numExtraDetour,
                    'latency': args.latency,
                    'bandwidth': args.bandwidth,
                    'data_rate': args.dataRateAccess,
                    'parasite_rate': args.dataRateExt,
                    'packet_size': args.packetSize,
                    'proto': args.protocol,
                    'meanexp': args.meanExpo,
                    'meanexppara': args.meanExpoPara,
                    "path": path,
                     "is_direct": is_direct,
                     "id": id,
                     "hop": hop,
                     "total_packets": total_packets,
                     "total_bits": total_bits,
                     "duration_s": duration,
                     "data_rate_bps": bandwidth_bps,
                     "packets_ps": packets_ps
    })                    

parser = argparse.ArgumentParser()

#-t simulationTime -l latency -h dataRate -e dataRateExt
parser.add_argument("-f", "--file", dest= "file", 
                    default="ninth", help="File name")
parser.add_argument("-t", "--simulationTime", dest= "simulationTime", 
                    default=5, help="Duration of the simulation", type=float)
parser.add_argument("-l", "--latency", dest= "latency", 
                    default="10ms", help="Latency of the links")
parser.add_argument("-b", "--bandwidth", dest= "bandwidth", 
                    default="100bps", help="Bandwidth of the links")
parser.add_argument("-a", "--dataRateAccess", dest= "dataRateAccess", 
                    default="10bps", help="Data rate of the links")
parser.add_argument("-e", "--dataRateExt", dest= "dataRateExt", 
                    default="10bps", help="Data rate of the external links")
parser.add_argument("-o", "--packetSize", dest= "packetSize", 
                    default=12000, help="Packet size in bits", type = int)
parser.add_argument("-p", "--protocol", dest= "protocol", 
                    default="Udp", help="Transport Protocol: Tcp ou Udp")
parser.add_argument("-i", "--numExtraRouters", dest= "numExtraRouters", 
                    default=0, help="Number of intermediate nodes between A0 and D0", type=int)
parser.add_argument("-d", "--numExtraDetour", dest= "numExtraDetour", 
                    default=0, help="Number of intermediate nodes between D2 and D1", type=int)
parser.add_argument("-m", "--meanExpo", dest= "meanExpo", 
                    default=0.5, help="Mean of the exponential variable modeling inter-arrival time", type=float)
parser.add_argument("-x", "--meanExpoPara", dest= "meanExpoPara", 
                    default=0.5, help="Mean of the exponential variable modeling inter-arrival time of parasite packets", type=float)
parser.add_argument("-r", "--repertory", dest= "repertory", 
                    default="scratch/ninth/", help="Repertory for output files")

args = parser.parse_args()

#simulationTime = 5 # in s
prefixfile = args.repertory + "/"
namefile = "T"+format(args.simulationTime, 'f') + "s_" + "h" + str(args.numExtraRouters) + "_" + "a" + str(args.numExtraDetour) + "_"+ "L" + args.latency + "_B"+args.bandwidth + "_Ra"+args.dataRateAccess +"_Re"+ args.dataRateExt + "_P"+ str(args.packetSize) + "b_" + args.protocol + "_Ma" + format(args.meanExpo, 'f') + "_Me"+ format(args.meanExpoPara, 'f') +"_"

print(prefixfile + namefile + "bandwidth.csv")
file_bandwidth = open(prefixfile + namefile + "bandwidth.csv", "a+")

file_size = os.path.getsize(prefixfile + namefile + "bandwidth.csv") 
print("file_size: ", file_size)
header = 50
nb_path = 5
one_block_of_path = 2096
cnt_ID = max (0, ((file_size - header) // one_block_of_path) * nb_path)
#sum(1 for _ in file_bandwidth)
print("cnt_ID: ", cnt_ID)

fieldnames = ['simulation_time','extra_router','extra_detour', 'latency', 'bandwidth', 'data_rate', 'parasite_rate','packet_size', 'proto','meanexp', 'meanexppara',"path","is_direct", "id","hop","total_packets", "total_bits","duration_s","data_rate_bps","packets_ps"]
writer = csv.DictWriter(file_bandwidth, fieldnames=fieldnames, delimiter=';')

if 0 == cnt_ID and 0 == file_size:
    writer.writeheader()




path = "direct"
is_direct = True
id = cnt_ID
file = prefixfile + namefile + "ninth-distLink-0-0.tr"
option = "+"
hop = "A0 - linked ..."
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-2-0.tr"
option = "r"
hop = "D0 - linked ..."
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-2-1.tr"
option = "+"
hop = "D0 - linked D1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-3-2.tr"
option = "r"
hop = "D1 - linked D0"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-3-0.tr"
option = "+"
hop = "D1 - linked A1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-1-0.tr"
option = "r"
hop = "A1 - linked D1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)



path = "detour"
is_direct = False
id = id + 1
file = prefixfile + namefile + "ninth-distLink-0-0.tr"
option = "+"
hop = "A0 - linked ..."
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-2-0.tr"
option = "r"
hop = "D0 - linked ..."
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-2-2.tr"
option = "+"
hop = "D0 - linked D2"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-4-0.tr"
option = "r"
hop = "D2 - linked D0"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-4-1.tr"
option = "+"
hop = "D2 - linked D1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-backbone-3-3.tr"
option = "r"
hop = "D1 - linked D2"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-3-1.tr"
option = "+"
hop = "D1 - linked A1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

file = prefixfile + namefile + "ninth-distLink-1-1.tr"
option = "r"
hop = "A1 - linked D1"
read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)



# path = "ext1_detour"
# is_direct = False
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-5-0.tr"
# option = "+"
# hop = "E0 - linked D0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-2-3.tr"
# option = "r"
# hop = "D0 - linked E0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-2-2.tr"
# option = "+"
# hop = "D0 - linked D2"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-4-0.tr"
# option = "r"
# hop = "D2 - linked D0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-4-1.tr"
# option = "+"
# hop = "D2 - linked D1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-3-3.tr"
# option = "r"
# hop = "D1 - linked D2"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# # file = prefixfile + namefile + "ninth-ext-3-5.tr"
# # option = "+"
# # hop = "D1 - linked E1"
# # read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# # file = prefixfile + namefile + "ninth-ext-6-1.tr"
# # option = "r"
# # hop = "E1 - linked D1"
# # read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)






# path = "ext1_direct"
# is_direct = True
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-5-0.tr"
# option = "+"
# hop = "E0 - linked D0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)
# file = prefixfile + namefile + "ninth-ext-2-3.tr"
# option = "r"
# hop = "D0 - linked E0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-2-1.tr"
# option = "+"
# hop = "D0 - linked D1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-3-2.tr"
# option = "r"
# hop = "D1 - linked D0"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-3-4.tr"
# option = "+"
# hop = "D1 - linked E1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-6-0.tr"
# option = "r"
# hop = "E1 - linked D1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)


# path = "ext2"
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-7-0.tr"
# option = "+"
# hop = "E2 - linked D2"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-4-2.tr"
# option = "r"
# hop = "D2 - linked E2"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-4-1.tr"
# option = "+"
# hop = "D2 - linked D1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-backbone-3-3.tr"
# option = "r"
# hop = "D1 - linked D2"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-3-4.tr"
# option = "+"
# hop = "D1 - linked E1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)

# file = prefixfile + namefile + "ninth-ext-6-0.tr"
# option = "r"
# hop = "E1 - linked D1"
# read_and_write_bandwidth(args, file, option, writer, path, id, hop, is_direct)


file_bandwidth.close()