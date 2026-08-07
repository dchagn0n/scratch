from scapy.all import rdpcap, IP, UDP, TCP
import csv
import glob
import pandas as pd 
import os
import argparse


# def extract_packet_info(pcap_file, interface_label): 
#     packets = rdpcap(pcap_file) 
#     data = [] 
#     for pkt in packets: 
#         if IP in pkt: 
#             proto = 'TCP'if TCP in pkt else ('UDP' if UDP in pkt else 'OTHER')
#             row = { 
#                 'timestamp': pkt.time, 
#                 'interface': interface_label, 
#                 'src': pkt[IP].src, 
#                 'dst': pkt[IP].dst, 
#                 'ip_id': pkt[IP].id, 
#                 'proto': proto, 
#                 'sport': pkt[TCP].sport if TCP in pkt else (pkt[UDP].sport if UDP in pkt else None), 
#                 'dport': pkt[TCP].dport if TCP in pkt else (pkt[UDP].dport if UDP in pkt else None), 
#                 'length': len(pkt) 
#                 } 
#             if proto == 'TCP': 
#                 row['seq'] = pkt[TCP].seq 
#             elif proto == 'UDP': 
#                 row['seq'] = None 
#             data.append(row) 
#     return data

# --- Chercher tous les fichiers .pcap dans le dossier courant

parser = argparse.ArgumentParser()

#-t simulationTime -l latency -h dataRate -e dataRateExt
parser.add_argument("-f", "--file", dest= "file", 
                    default="ninth", help="File name")
parser.add_argument("-t", "--simulationTime", dest= "simulationTime", 
                    default=5, help="Duration of the simulation", type=float)
parser.add_argument("-l", "--latency", dest= "latency", 
                    default="5ms", help="Latency of the links")
parser.add_argument("-b", "--bandwidth", dest= "bandwidth", 
                    default="100Mbps", help="Bandwidth of the links")
parser.add_argument("-a", "--dataRateAccess", dest= "dataRateAccess", 
                    default="10Mbps", help="Data rate of the links")
parser.add_argument("-e", "--dataRateExt", dest= "dataRateExt", 
                    default="10Mbps", help="Data rate of the external links")
parser.add_argument("-o", "--packetSize", dest= "packetSize", 
                    default=12000, help="Packet size in bits", type = int)
parser.add_argument("-p", "--protocol", dest= "protocol", 
                    default="Tcp", help="Transport Protocol: Tcp ou Udp")
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
namefile = "T"+format(args.simulationTime, 'f') + "s_" + "h" + str(args.numExtraRouters) + "_"+ "a" + str(args.numExtraDetour) + "_"+ "L" + args.latency + "_B"+args.bandwidth + "_Ra"+args.dataRateAccess +"_Re"+ args.dataRateExt + "_P"+ str(args.packetSize) + "b_" + args.protocol + "_Ma" + format(args.meanExpo, 'f') + "_Me"+ format(args.meanExpoPara, 'f') +"_"

print(prefixfile + namefile + "trace-*.pcap")
pcap_files = glob.glob(prefixfile + namefile + "trace-*.pcap")

# Stocker les observations
observations = []
# --- Ouvrir un fichier CSV global pour tous les résultats
with open(prefixfile + namefile + "trace_all_output_stats.csv", mode='w', newline='') as csv_file:
    fieldnames = ['simulation_time','extra_router','extra_detour', 'latency', 'bandwidth', 'data_rate', 'parasite_rate','packet_size', 'proto', 'meanexp', 'meanexppara', 'file', 'packet_num', 'timestamp', 'src_ip', 'dst_ip', 'ip_id', 'protocol', 'src_port', 'dst_port', 'length']
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames, delimiter=';')
    writer.writeheader()

    # --- Parcourir tous les fichiers pcap
    for pcap_file in pcap_files:
        print(f"Processing {pcap_file}")
        packets = rdpcap(pcap_file)

        for i, pkt in enumerate(packets, start=1):
            src_ip = dst_ip = proto = ip_id = src_port = dst_port = None

            if pkt.haslayer("IP"):
                src_ip = pkt["IP"].src
                dst_ip = pkt["IP"].dst
                proto = pkt["IP"].proto
                ip_id = pkt["IP"].id

                if pkt.haslayer("TCP"):
                    src_port = pkt["TCP"].sport
                    dst_port = pkt["TCP"].dport
                    proto = "TCP"
                elif pkt.haslayer("UDP"):
                    src_port = pkt["UDP"].sport
                    dst_port = pkt["UDP"].dport
                    proto = "UDP"
                elif pkt.haslayer("ICMP"):
                    proto = "ICMP"
                flow_key = (
                    proto,
                    src_ip,
                    dst_ip,
                    src_port,
                    dst_port,
                    ip_id,
                )
                observations.append({
                    "file": pcap_file,
                    "timestamp": pkt.time,
                    "flow_key": flow_key,
                    "length": len(pkt),
                })

            # # Par un filtre sur le nom de fichier qui identifie les liens d'intérêt :
            # pcap_basename = os.path.basename(pcap_file)
            # is_interest_link = any(tag in pcap_basename for tag in [
            #     "trace-access0-access",          # lien A0 sortant
            #     "trace-dist0-dist1",             # backbone D0→D1
            #     "trace-dist0-dist2",             # backbone D0→D2
            #     "trace-dist2-dist1",             # backbone détour →D1
            #     "trace-dist1-access1-direct",    # D1→A1 direct  (après correction bug 2)
            #     "trace-dist1-access1-detour",    # D1→A1 détour  (après correction bug 2)
            # ])
            # if is_interest_link:  # remplace le filtre src_ip
            if src_ip == "10.1.9.1": ## 10.1.9.1 ??
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
                    'file': pcap_file,
                    'packet_num': i,
                    'timestamp': pkt.time,
                    'src_ip': src_ip,
                    'dst_ip': dst_ip,
                    'ip_id': ip_id,
                    'protocol': proto,
                    'src_port': src_port,
                    'dst_port': dst_port,
                    'length': len(pkt)
                })

print("✅ Tous les fichiers pcap sont extraits dans '"+ prefixfile + namefile + "trace_all_output_stats.csv'")


# # Convertir en DataFrame
# df_obs = pd.DataFrame(observations)

# # Compter les sauts par flow_key
# grouped = df_obs.groupby("flow_key").agg({
#     "file": "count",
#     "timestamp": ["min", "max"],
# })

# grouped.columns = ["hop_count", "first_seen", "last_seen"]
# grouped = grouped.reset_index()

# # Sauvegarder pour analyse
# grouped.to_csv(prefixfile + namefile + "flow_hop_analysis.csv", index=False)
# print("✅ Analyse exportée vers "+prefixfile + namefile + "flow_hop_analysis.csv")