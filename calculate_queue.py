import argparse
import csv
import os


def read_and_write_queue(args, file, option, writer, path, id, hop):
    nb_enqueue = 0
    nb_dequeue = 0
    nb_inqueue = 0
    nb_dropped = 0
    nb_received = 0
    nb_indevice = 0

    with open(file, "r") as trace_file:
        for line in trace_file:
            op = line.split()[0]
            if "r" == op:
                time = float(line.split()[1]) 
                nb_received += 1
                nb_indevice += 1
                
                
            elif "+" == op:
                time = float(line.split()[1]) 
                nb_enqueue += 1
                nb_inqueue += 1
            
            elif "-" == op:
                time = float(line.split()[1]) 
                nb_dequeue += 1
                nb_inqueue -= 1

            elif "d" == op:
                time = float(line.split()[1]) 
                nb_dropped += 1
                nb_indevice -= 1

            elif "dest" == option:
                op = option
                line_split = line.split(";")
                print(line_split)
                time = float(line_split[0]) 
                nb_inqueue = int(line_split[2])

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
                     "id": id,
                     "hop": hop,
                     "time": time,
                     "op": op,
                     "nb_enqueue": nb_enqueue,
                     "nb_dequeue": nb_dequeue,
                     "nb_inqueue": nb_inqueue,
                     "nb_dropped": nb_dropped,
                     "nb_received": nb_received,
                     "nb_indevice": nb_indevice
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

analysis_type = "queue"
print(prefixfile + namefile + analysis_type +".csv")
file_queue = open(prefixfile + namefile + analysis_type +".csv", "a+")

file_size = os.path.getsize(prefixfile + namefile + analysis_type +".csv") 
print("file_size: ", file_size)
header = 50
nb_path = 5
one_block_of_path = 2096
cnt_ID = max (0, ((file_size - header) // one_block_of_path) * nb_path)
#sum(1 for _ in file_bandwidth)
print("cnt_ID: ", cnt_ID)

fieldnames = ['simulation_time','extra_router','extra_detour', 'latency', 'bandwidth', 'data_rate', 'parasite_rate','packet_size', 'proto', 'meanexp', 'meanexppara',"path", "id", "hop","time","op","nb_enqueue", "nb_dequeue","nb_inqueue","nb_dropped","nb_received", "nb_indevice"]
writer = csv.DictWriter(file_queue, fieldnames=fieldnames, delimiter=';')

if 0 == cnt_ID and 0 == file_size:
    writer.writeheader()




path = "direct"
id = file_size
file = prefixfile + namefile + "ninth-distLink-0-0.tr"
option = "+"
hop = "A0 - linked ..."
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-distLink-2-0.tr"
option = "r"
hop = "D0 - linked ..."
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-2-1.tr"
option = "+"
hop = "D0 - linked D1"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-3-2.tr"
option = "r"
hop = "D1 - linked D0"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-distLink-3-0.tr"
option = "+"
hop = "D1 - linked A1"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "distDevices1_direct-packetsInQueue.txt"
option = "dest"
hop = "A1 - linked D1"
read_and_write_queue(args, file, option, writer, path, id, hop)



path = "detour"
id = id + 1
file = prefixfile + namefile + "ninth-distLink-0-0.tr"
option = "+"
hop = "A0 - linked ..."
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-distLink-2-0.tr"
option = "r"
hop = "D0 - linked ..."
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-2-2.tr"
option = "+"
hop = "D0 - linked D2"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-4-0.tr"
option = "r"
hop = "D2 - linked D0"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-4-1.tr"
option = "+"
hop = "D2 - linked D1"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-backbone-3-3.tr"
option = "r"
hop = "D1 - linked D2"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "ninth-distLink-3-1.tr"
option = "+"
hop = "D1 - linked A1"
read_and_write_queue(args, file, option, writer, path, id, hop)

file = prefixfile + namefile + "distDevices1_detour-packetsInQueue.txt"
option = "dest"
hop = "A1 - linked D1"
read_and_write_queue(args, file, option, writer, path, id, hop)



# path = "ext1_detour"
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-5-0.tr"
# option = "+"
# hop = "E0 - linked D0"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-2-3.tr"
# option = "r"
# hop = "D0 - linked E0"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-2-2.tr"
# option = "+"
# hop = "D0 - linked D2"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-4-0.tr"
# option = "r"
# hop = "D2 - linked D0"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-4-1.tr"
# option = "+"
# hop = "D2 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-3-3.tr"
# option = "r"
# hop = "D1 - linked D2"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-3-5.tr"
# option = "+"
# hop = "D1 - linked E1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-6-1.tr"
# option = "r"
# hop = "E1 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)






# path = "ext1_direct"
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-5-0.tr"
# option = "+"
# hop = "E0 - linked D0"
# read_and_write_queue(args, file, option, writer, path, id, hop)
# file = prefixfile + namefile + "ninth-ext-2-3.tr"
# option = "r"
# hop = "D0 - linked E0"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-2-1.tr"
# option = "+"
# hop = "D0 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-3-2.tr"
# option = "r"
# hop = "D1 - linked D0"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-3-4.tr"
# option = "+"
# hop = "D1 - linked E1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-6-0.tr"
# option = "r"
# hop = "E1 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)


# path = "ext2"
# id = id + 1
# file = prefixfile + namefile + "ninth-ext-7-0.tr"
# option = "+"
# hop = "E2 - linked D2"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-4-2.tr"
# option = "r"
# hop = "D2 - linked E2"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-4-1.tr"
# option = "+"
# hop = "D2 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-backbone-3-3.tr"
# option = "r"
# hop = "D1 - linked D2"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-3-4.tr"
# option = "+"
# hop = "D1 - linked E1"
# read_and_write_queue(args, file, option, writer, path, id, hop)

# file = prefixfile + namefile + "ninth-ext-6-0.tr"
# option = "r"
# hop = "E1 - linked D1"
# read_and_write_queue(args, file, option, writer, path, id, hop)


file_queue.close()
