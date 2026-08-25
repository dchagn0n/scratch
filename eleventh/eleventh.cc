#include "ns3/applications-module.h"
#include "ns3/core-module.h"
#include "ns3/flow-monitor-helper.h"
#include "ns3/internet-module.h"
#include "ns3/ipv4-global-routing-helper.h"
#include "ns3/network-module.h"
#include "ns3/point-to-point-module.h"
#include "ns3/traffic-control-module.h"

#include "ns3/ipv4-routing-table-entry.h"
#include "ns3/ipv4-static-routing-helper.h"
#include "ns3/ipv4-global-routing.h"
#include "ns3/output-stream-wrapper.h"
#include "ns3/ping-helper.h"
#include "ns3/netanim-module.h"
#include "ns3/ipv4-flow-probe.h"
#include "ns3/random-variable-stream.h"

#include "ns3/trace-helper.h"
#include "ns3/v4traceroute-helper.h"

#include "ns3/netanim-module.h"


#include <cassert>
#include <chrono>
#include <cmath>
#include <deque>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <random>
#include <regex>  // Ajout pour utiliser regex
#include <string>
#include <vector>



using namespace ns3;



NS_LOG_COMPONENT_DEFINE("SimpleGlobalRoutingExample");

void
PacketsInQueueTrace(Ptr<OutputStreamWrapper> stream, uint32_t oldValue, uint32_t newValue)
{
    *stream->GetStream() << Simulator::Now().GetSeconds() << ";" << oldValue << ";" << newValue << std::endl;
}

const double PI = std::acos(-1);

struct Point {
    double x, y;
};

std::vector<Point> GenerateSemiCirclePointsFromDiameter(double X1, double Y1, double X2, double Y2, int n) {
    std::vector<Point> points;
    if (n < 2) return points;

    // Centre du cercle
    double Cx = (X1 + X2) / 2.0;
    double Cy = (Y1 + Y2) / 2.0;

    // Vecteur diamètre et norme
    double dx = X2 - X1;
    double dy = Y2 - Y1;
    double d = std::sqrt(dx*dx + dy*dy);
    double radius = d / 2.0;

    // Base orthonormée
    double ux = dx / d;
    double uy = dy / d;
    // Vecteur perpendiculaire (vers le "haut" du demi-cercle)
    double vx = -uy;
    double vy = ux;

    for (int i = 0; i < n; ++i) {
        double theta = PI * i / (n - 1); // angle de 0 à pi
        double localX = radius * std::cos(theta);
        double localY = radius * std::sin(theta);

        // Changement de repère : (u, v) → coordonnées globales
        double x = Cx + localX * ux + localY * vx;
        double y = Cy + localX * uy + localY * vy;

        points.push_back({x, y});
    }

    return points;
}

float parseRateToBps(const std::string& rate) {
    size_t pos = rate.find("bps");
    if (pos == std::string::npos) {
        throw std::invalid_argument("Invalid rate format: missing 'bps'");
    }

    // Default multiplier (bps)
    float multiplier = 1.0;

    // Check the character just before "bps"
    if (pos >= 1) {
        char unit = rate[pos - 1];
        if (unit == 'G') {
            multiplier = 1e9;
            pos -= 1;
        } else if (unit == 'M') {
            multiplier = 1e6;
            pos -= 1;
        } else if (unit == 'K') {
            multiplier = 1e3;
            pos -= 1;
        }
        // else → no unit prefix
    }

    // Extract numeric part
    std::string numberPart = rate.substr(0, pos);
    float value = std::stof(numberPart);
    return value * multiplier;
}













int
main(int argc, char* argv[])
{
    auto start = std::chrono::high_resolution_clock::now();

    bool enableFlowMonitor = true;
    uint32_t scaleFactor = 1;  // Facteur d'échelle pour ajuster la taille du réseau
    std::string bandwidth = "100bps";
    std::string bandwidth_ext = bandwidth;
    std::string dataRateAccess = "10bps";
    std::string dataRateExt = "10bps";
    uint32_t packetSize = 12000;  // Taille des paquets (en bits)
    std::string latency_direct = "5ms";
    std::string latency_detour = "2ms";

    std::string transportProt = "Udp";
    std::string socketType;
    std::string socketType_Ext = "ns3::UdpSocketFactory";

    float startTime = 0.01F; // in s
    float simulationTime = 10; // in s
    
    uint32_t numExtraRouters = 0;
    uint32_t numExtraDetour = 3;

    double exp_mean = 0.5;
    double exp_mean_para = 0.5;

    std::string repertory = "scratch/ninth/";

    CommandLine cmd(__FILE__);
    
    cmd.AddValue("EnableMonitor", "Enable Flow Monitor", enableFlowMonitor);
    cmd.AddValue("ScaleFactor", "Scale factor for the network", scaleFactor); // Permet de modifier l'échelle
    cmd.AddValue("transportProt", "Transport protocol to use: Tcp, Udp", transportProt);
    cmd.AddValue("simulationTime", "Duration of the simulation", simulationTime);
    cmd.AddValue("bandwidth", "Bandwidth of the links", bandwidth);
    cmd.AddValue("dataRateAccess", "Data rate of the access links", dataRateAccess);
    cmd.AddValue("dataRateExt", "Data rate of the external links", dataRateExt);
    cmd.AddValue("latency", "Latency of the links", latency_direct);
    cmd.AddValue("packetSize", "Packet size in bits", packetSize);
    cmd.AddValue("numExtraRouters", "Number of extra routers between A0 and D0", numExtraRouters);
    cmd.AddValue("numExtraDetour", "Number of extra routers between D2 and D1", numExtraDetour);
    cmd.AddValue("meanExpo", "Mean of the exponential variable modeling inter-arrival time", exp_mean);
    cmd.AddValue("meanExpoPara", "Mean of the exponential variable modeling inter-arrival time of parasite packets", exp_mean_para);
    cmd.AddValue("repertory", "Repertory for output files", repertory);



    cmd.Parse(argc, argv);

    // Compute a 32-bit hash from the string
    uint32_t seed = static_cast<uint32_t>(std::hash<std::string>{}(repertory));
    // You may also want to use a different value for SetRun if you run multiple simulations
    uint32_t run = seed % 10000; // example: derived smaller run index
    RngSeedManager::SetSeed(seed);
    RngSeedManager::SetRun(run);

    std::cout << "Using seed = " << seed << " and run = " << run << std::endl;

    if (transportProt == "Tcp")
    {
        socketType = "ns3::TcpSocketFactory";
    }
    else
    {
        socketType = "ns3::UdpSocketFactory";
    }

    std::string prefixfile = repertory + "/";
    std::string namefile = "T"+std::to_string(simulationTime) + "s_h" + std::to_string(numExtraRouters) + "_a" + std::to_string(numExtraDetour) + "_"
    + "L"+latency_direct+ "_B"+bandwidth + "_Ra"+dataRateAccess +"_Re"+dataRateExt + "_P"+std::to_string(packetSize) + "b_" + transportProt + "_Ma" + std::to_string(exp_mean) + "_Me" + std::to_string(exp_mean_para) + "_";
    std::cout << prefixfile << namefile << std::endl;

    // latency of detour path is half of the direct path
    int pos = latency_direct.find("ms");
    uint32_t latency_direct_float = std::stof(latency_direct.substr(0,pos));
    latency_detour = std::to_string(latency_direct_float/2) + "ms";
    latency_detour = latency_direct;
    std::cout << "latency detour: " << latency_detour << std::endl;

    std::cout << "bandwidth: " << bandwidth << std::endl;

    float bandwidth_float = parseRateToBps(bandwidth); 
    
    std::cout << "dataRateAccess: " << dataRateAccess << std::endl;

    // bandwidth of external links
    float dataRateExt_float = parseRateToBps(dataRateExt); 

    if (dataRateExt_float >= bandwidth_float)// 
    {
        bandwidth_ext = std::to_string(2*dataRateExt_float) + "bps"; 
    }else{
        bandwidth_ext = bandwidth;
    }
    std::cout << "bandwidth_ext: " << bandwidth_ext << std::endl;
    std::cout << "dataRateExt: " << dataRateExt << std::endl;

    float dataRateExt_D0_float = dataRateExt_float; // * (2 + numExtraDetour);  // equilibre les fluxs détournés et directes vers D1
    std::string dataRateExt_D0 = std::to_string(dataRateExt_D0_float) + "bps"; 
    std::cout << "dataRateExt_D0: " << dataRateExt_D0 << std::endl;

    float stopTime = startTime + simulationTime;

    

    // Create nodes
    NodeContainer accessRouters, distRouters;
    NodeContainer external0Nodes, external1Nodes, external2Nodes;
    
    accessRouters.Create(2); // Un routeur pour chaque site d'accès
    distRouters.Create(3); // Un routeur pour chaque site de distribution
    external0Nodes.Create(1);// * scaleFactor); //nœuds parasites sur d0
    external1Nodes.Create(1);//* scaleFactor); //nœuds parasites sur D1
    external2Nodes.Create(1);//* scaleFactor); //nœuds parasites sur D2
    
    NodeContainer extraRouters, extraDetour;
    NodeContainer parasiteNodes, parasiteDetour;

    if (numExtraRouters > 0)
    {
        extraRouters.Create(numExtraRouters); // Nœuds supplémentaires pour allonger le chemin
        parasiteNodes.Create(numExtraRouters); // Un parasite par routeur
    }

    if (numExtraDetour > 0)
    {
        extraDetour.Create(numExtraDetour);
        parasiteDetour.Create(numExtraDetour); // Un parasite par routeur de détour
    }


    


    // Distribution links
    PointToPointHelper distLink;
    distLink.SetDeviceAttribute("DataRate", StringValue(bandwidth));
    distLink.SetChannelAttribute("Delay", StringValue(latency_direct));
    distLink.SetQueue("ns3::DropTailQueue", "MaxSize", StringValue("3000p")); // 3000 paquets

    NetDeviceContainer distDevices0_direct;
    std::vector<NetDeviceContainer> chainDevices;
    NodeContainer left = accessRouters.Get(0); // A0
    if (numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            NodeContainer right = extraRouters.Get(i);
            chainDevices.push_back(distLink.Install(left.Get(0), right.Get(0)));

            left = right; // Chaînage
        }
        // Dernier → D0
        chainDevices.push_back(distLink.Install(extraRouters.Get(numExtraRouters - 1), distRouters.Get(0)));
    }else{
         distDevices0_direct= distLink.Install(accessRouters.Get(0), distRouters.Get(0));
    }

    
    NetDeviceContainer distDevices1_direct = distLink.Install(accessRouters.Get(1), distRouters.Get(1));
    NetDeviceContainer distDevices1_detour = distLink.Install(accessRouters.Get(1), distRouters.Get(1));



    // Backbone links
    PointToPointHelper backbone_direct;
    backbone_direct.SetDeviceAttribute("DataRate", StringValue(bandwidth));
    backbone_direct.SetChannelAttribute("Delay", StringValue(latency_direct));
    backbone_direct.SetQueue("ns3::DropTailQueue", "MaxSize", StringValue("3000p")); // 3000 paquets


    NetDeviceContainer backbone01 = backbone_direct.Install(distRouters.Get(0), distRouters.Get(1));

    PointToPointHelper backbone_detour;
    backbone_detour.SetDeviceAttribute("DataRate", StringValue(bandwidth));
    backbone_detour.SetChannelAttribute("Delay", StringValue(latency_detour));
    backbone_detour.SetQueue("ns3::DropTailQueue", "MaxSize", StringValue("3000p")); // 3000 paquets
    NetDeviceContainer backbone02 = backbone_detour.Install(distRouters.Get(0), distRouters.Get(2));

    std::vector<NetDeviceContainer> detourChainDevices;
    NodeContainer prevNode = distRouters.Get(2);

    for (uint32_t i = 0; i < numExtraDetour; ++i)
    {
        //NodeContainer nextNode = (i == numExtraDetour - 1) ? distRouters.Get(1) : extraDetour.Get(i + 1);
        NetDeviceContainer devices = backbone_detour.Install(prevNode.Get(0), extraDetour.Get(i));
        detourChainDevices.push_back(devices);

        prevNode = extraDetour.Get(i);
    }
    NetDeviceContainer backbone21 = backbone_detour.Install(prevNode.Get(0), distRouters.Get(1)); //distRouters.Get(2)
    detourChainDevices.push_back(backbone21);

    
    

    //  External links
    PointToPointHelper extHelper;
    extHelper.SetDeviceAttribute("DataRate", StringValue(bandwidth_ext));
    extHelper.SetChannelAttribute("Delay", StringValue(latency_direct));
    extHelper.SetQueue("ns3::DropTailQueue", "MaxSize", StringValue("3000p")); // 3000 paquets

    NetDeviceContainer extDev0 = extHelper.Install(external0Nodes.Get(0), distRouters.Get(0));
    NetDeviceContainer extDev1_direct = extHelper.Install(external1Nodes.Get(0), distRouters.Get(1)); // extDev1_direct
    // NetDeviceContainer extDev1_detour = extHelper.Install(external1Nodes.Get(0), distRouters.Get(1));
    NetDeviceContainer extDev2 = extHelper.Install(external2Nodes.Get(0), distRouters.Get(2));

    std::vector<NetDeviceContainer> parasiteDevices;

    if(numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            // Parasite vers le routeur
            parasiteDevices.push_back(extHelper.Install(parasiteNodes.Get(i), extraRouters.Get(i)));
        }
    }

    std::vector<NetDeviceContainer> detourParasiteDevices;
    for (uint32_t i = 0; i < numExtraDetour; ++i)
    {
        // Parasite vers le routeur
        detourParasiteDevices.push_back(extHelper.Install(parasiteDetour.Get(i), extraDetour.Get(i)));
    }

    // Install Internet stack
    InternetStackHelper stack;
    stack.Install(accessRouters);
    stack.Install(distRouters);
    stack.Install(external0Nodes);
    stack.Install(external1Nodes);
    stack.Install(external2Nodes);
    if (numExtraRouters > 0)
    {
        stack.Install(extraRouters);
        stack.Install(parasiteNodes);
    }
    if (numExtraDetour > 0)
    {
        stack.Install(extraDetour);
        stack.Install(parasiteDetour);
    }


    // IP addressing
    Ipv4AddressHelper address;
    address.SetBase("10.1.1.0", "255.255.255.0");
    Ipv4InterfaceContainer lan0_direct;
    //Ipv4InterfaceContainer lan0_direct = address.Assign(distDevices0_direct);

    address.NewNetwork();
    Ipv4InterfaceContainer lan1_direct = address.Assign(distDevices1_direct);

    //address.SetBase("10.1.8.0", "255.255.255.0");
    address.NewNetwork();
    Ipv4InterfaceContainer lan1_detour = address.Assign(distDevices1_detour);

    //address.SetBase("10.1.3.0", "255.255.255.0");
    address.NewNetwork();
    Ipv4InterfaceContainer iface01 = address.Assign(backbone01);

    //address.SetBase("10.1.4.0", "255.255.255.0");
    address.NewNetwork();
    Ipv4InterfaceContainer iface02 = address.Assign(backbone02);

    

    //address.SetBase("10.1.6.0", "255.255.255.0");
    address.NewNetwork();
    Ipv4InterfaceContainer ext0Interfaces = address.Assign(extDev0);
    
    //address.SetBase("10.1.7.0", "255.255.255.0");
    address.NewNetwork();
    Ipv4InterfaceContainer ext1Interfaces_direct = address.Assign(extDev1_direct);
    
    //address.NewNetwork();
    //Ipv4InterfaceContainer ext1Interfaces_detour = address.Assign(extDev1_detour);

    address.NewNetwork();
    Ipv4InterfaceContainer ext2Interfaces = address.Assign(extDev2);
    

    std::vector<Ipv4InterfaceContainer> chainIfaces;
    std::vector<Ipv4InterfaceContainer> parasiteIfaces;
    if(numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < chainDevices.size(); ++i)
        {
            address.NewNetwork();
            chainIfaces.push_back(address.Assign(chainDevices[i]));
        }

        for (uint32_t i = 0; i < parasiteDevices.size(); ++i)
        {
            address.NewNetwork();
            parasiteIfaces.push_back(address.Assign(parasiteDevices[i]));
        }
    }else{
        address.NewNetwork();
        lan0_direct = address.Assign(distDevices0_direct);
    }


    std::vector<Ipv4InterfaceContainer> detourChainIfaces, detourParasiteIfaces;
    Ipv4InterfaceContainer iface21;
    uint32_t detourchainsize = detourChainDevices.size();
    for (uint32_t i = 0; i < detourchainsize; ++i)
    {
        address.NewNetwork();
        iface21 = address.Assign(detourChainDevices[i]);
        detourChainIfaces.push_back(iface21);
    }
    // address.NewNetwork();
    //  

    for (uint32_t i = 0; i < detourParasiteDevices.size(); ++i)
    {
        address.NewNetwork();
        detourParasiteIfaces.push_back(address.Assign(detourParasiteDevices[i]));
    }

    

    
    AsciiTraceHelper ascii;
    

    // second try
    Ptr<NetDevice> nddirect = distDevices1_direct.Get(0); // L’interface de sortie du client
    Ptr<PointToPointNetDevice> ptpNddirect = DynamicCast<PointToPointNetDevice>(nddirect);
    Ptr<Queue<Packet>> txQueuedirect = ptpNddirect->GetQueue();
    Ptr<OutputStreamWrapper> streamPacketsInQueuedirect = ascii.CreateFileStream(prefixfile + namefile + "distDevices1_direct-packetsInQueue.txt");
    txQueuedirect->TraceConnectWithoutContext("PacketsInQueue", MakeBoundCallback(&PacketsInQueueTrace, streamPacketsInQueuedirect));
    

    Ptr<NetDevice> nddetour = distDevices1_detour.Get(0); // L’interface de sortie du client
    Ptr<PointToPointNetDevice> ptpNddetour = DynamicCast<PointToPointNetDevice>(nddetour);
    Ptr<Queue<Packet>> txQueuedetour = ptpNddetour->GetQueue();
    Ptr<OutputStreamWrapper> streamPacketsInQueuedetour = ascii.CreateFileStream(prefixfile + namefile + "distDevices1_detour-packetsInQueue.txt");
    txQueuedetour->TraceConnectWithoutContext("PacketsInQueue", MakeBoundCallback(&PacketsInQueueTrace, streamPacketsInQueuedetour));



    // Static routing setup
    

    Ipv4StaticRoutingHelper staticRouting;

    Ptr<Ipv4> ipv4_access0 = accessRouters.Get(0)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_access1 = accessRouters.Get(1)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_dist0 = distRouters.Get(0)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_dist1 = distRouters.Get(1)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_dist2 = distRouters.Get(2)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_ext0 = external0Nodes.Get(0)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_ext1 = external1Nodes.Get(0)->GetObject<Ipv4>();
    Ptr<Ipv4> ipv4_ext2 = external2Nodes.Get(0)->GetObject<Ipv4>();
    Ptr<Ipv4StaticRouting> staticAccess0 = staticRouting.GetStaticRouting(ipv4_access0);
    Ptr<Ipv4StaticRouting> staticAccess1 = staticRouting.GetStaticRouting(ipv4_access1);
    Ptr<Ipv4StaticRouting> staticDist0 = staticRouting.GetStaticRouting(ipv4_dist0);
    Ptr<Ipv4StaticRouting> staticDist1 = staticRouting.GetStaticRouting(ipv4_dist1);
    Ptr<Ipv4StaticRouting> staticDist2 = staticRouting.GetStaticRouting(ipv4_dist2);
    Ptr<Ipv4StaticRouting> staticExt0 = staticRouting.GetStaticRouting(ipv4_ext0);
    Ptr<Ipv4StaticRouting> staticExt1 = staticRouting.GetStaticRouting(ipv4_ext1);
    Ptr<Ipv4StaticRouting> staticExt2 = staticRouting.GetStaticRouting(ipv4_ext2);
    
    
    // Ptr<Ipv4StaticRouting> GetStaticRouting_me(Ptr<Node> node) {
    //     Ptr<Ipv4> ipv4 = node->GetObject<Ipv4>();
    //     return staticRouting.GetStaticRouting(ipv4);
    // }

    // Pour debug les address IP des interfaces.
    Ptr<Ipv4> ipv4 = accessRouters.Get(0)->GetObject<Ipv4>();
    for (uint32_t i = 0; i < ipv4->GetNInterfaces(); ++i)
    {
        std::cout << "Interface " << i << " has addresses:\n";
        for (uint32_t j = 0; j < ipv4->GetNAddresses(i); ++j)
        {
            std::cout << "  " << ipv4->GetAddress(i, j).GetLocal() << "\n";
        }
    }
    ///////////////////////////////////////

    Ipv4Address firstHop;
    if (numExtraRouters > 0)
    {
        firstHop = chainIfaces[0].GetAddress(1); // vers Ai_0
    } else {
        firstHop = lan0_direct.GetAddress(1); // vers D0
    }

    staticAccess0->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), firstHop, 1);
    staticAccess0->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), firstHop, 1);
    //staticAccess0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), firstHop, 1);
    //staticAccess0->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), firstHop, 1);
    

    if (numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < numExtraRouters - 1; ++i)
        {
            Ptr<Node> currentRouter = extraRouters.Get(i);
            Ipv4Address nextHop = chainIfaces[i + 1].GetAddress(1); // vers le suivant
            Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_extra);

            
            uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(chainDevices[i+1].Get(0));

            routing->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
            routing->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
            //routing->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHop, ifaceIndex);
        }

        Ptr<Node> currentRouter = extraRouters.Get(numExtraRouters - 1);
        Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> routingLast = staticRouting.GetStaticRouting(ipv4_extra);
        Ipv4Address nextHopToD0 = chainIfaces[numExtraRouters].GetAddress(1); // vers D0
        uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(chainDevices[numExtraRouters].Get(0));
        routingLast->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD0, ifaceIndex);
        routingLast->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD0, ifaceIndex);
        //routingLast->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHopToD0, ifaceIndex);
    }

    

    

    // Example route: From dist0 to dist1 via dist2
    uint32_t ifaceIndex = ipv4_dist0->GetInterfaceForDevice(backbone02.Get(0));
    staticDist0->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),iface02.GetAddress(1), ifaceIndex); 
    //staticDist0->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),iface02.GetAddress(1), ifaceIndex);
    
    ifaceIndex = ipv4_dist0->GetInterfaceForDevice(backbone01.Get(0));
    staticDist0->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),iface01.GetAddress(1), ifaceIndex); 
    //staticDist0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0) , Ipv4Mask("255.255.255.0"),iface01.GetAddress(1), ifaceIndex);
    
    ifaceIndex = ipv4_dist0->GetInterfaceForDevice(extDev0.Get(1));
    staticDist0->AddNetworkRouteTo(ext0Interfaces.GetAddress(0) , Ipv4Mask("255.255.255.0"),ext0Interfaces.GetAddress(0), ifaceIndex);



    Ipv4Address nextHopD2;
    if (numExtraDetour > 0)
    {
        nextHopD2 = detourChainIfaces[0].GetAddress(1); 
    } else {
        nextHopD2 = iface21.GetAddress(1); 
    }

    ifaceIndex = ipv4_dist2->GetInterfaceForDevice(detourChainDevices[0].Get(0));
    staticDist2->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),nextHopD2, ifaceIndex);  //iface21.GetAddress(1)
    //staticDist2->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),nextHopD2, ifaceIndex);

    ifaceIndex = ipv4_dist2->GetInterfaceForDevice(backbone02.Get(1));
    staticDist2->AddNetworkRouteTo(ext0Interfaces.GetAddress(0), Ipv4Mask("255.255.255.0"),iface02.GetAddress(0), ifaceIndex); 

    if (numExtraDetour > 0)
    {
        for (uint32_t i = 0; i < numExtraDetour - 1; ++i)
        {
            Ptr<Node> currentRouter = extraDetour.Get(i);
            Ipv4Address nextHop = detourChainIfaces[i + 1].GetAddress(1); // vers le suivant
            Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_extra);

            uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(detourChainDevices[i+1].Get(0));

            //routing->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
            routing->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
        }

        Ptr<Node> currentRouter = extraDetour.Get(numExtraDetour - 1);
        Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> routingLast = staticRouting.GetStaticRouting(ipv4_extra);
        Ipv4Address nextHopToD1 = detourChainIfaces[numExtraDetour].GetAddress(1); // vers D1
        uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(detourChainDevices[numExtraDetour].Get(0));
        //routingLast->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD1, ifaceIndex);
        routingLast->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD1, ifaceIndex);    
    }

  

    ifaceIndex = ipv4_dist1->GetInterfaceForDevice(distDevices1_direct.Get(1));
    staticDist1->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),lan1_direct.GetAddress(0), ifaceIndex);

    ifaceIndex = ipv4_dist1->GetInterfaceForDevice(distDevices1_detour.Get(1));
    staticDist1->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),lan1_detour.GetAddress(0), ifaceIndex);
    
    ifaceIndex = ipv4_dist1->GetInterfaceForDevice(backbone21.Get(1));
    staticDist1->AddNetworkRouteTo(ext0Interfaces.GetAddress(0), Ipv4Mask("255.255.255.0"),iface21.GetAddress(0), ifaceIndex); 

    ifaceIndex = ipv4_dist1->GetInterfaceForDevice(extDev1_direct.Get(1));
    staticDist1->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),ext1Interfaces_direct.GetAddress(0), ifaceIndex);

    // ifaceIndex = ipv4_dist1->GetInterfaceForDevice(extDev1_detour.Get(1));
    // staticDist1->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),ext1Interfaces_detour.GetAddress(0), ifaceIndex);

    // E0 : route par défaut vers D0 uniquement.
    // Le trafic parasite de E0 ne sortira que d'un saut backbone (D0→D1 ou D0→D2).
    ifaceIndex = ipv4_ext0->GetInterfaceForDevice(extDev0.Get(0));
    staticExt0->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), ext0Interfaces.GetAddress(1), ifaceIndex);
    //staticExt0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),ext0Interfaces.GetAddress(1), ifaceIndex);
    //staticExt0->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),ext0Interfaces.GetAddress(1), ifaceIndex);

    // E1 : routes de retour vers E0 conservées (cohérence topologique, même si E1 est désormais inactif
    // pour le trafic parasite — les parasites terminent maintenant sur D1/D2 et non sur E1).
    ifaceIndex = ipv4_ext1->GetInterfaceForDevice(extDev1_direct.Get(0));
    staticExt1->AddNetworkRouteTo(ext0Interfaces.GetAddress(0), Ipv4Mask("255.255.255.0"),ext1Interfaces_direct.GetAddress(1), ifaceIndex);
    // E1 → A1 direct
    ifaceIndex = ipv4_ext1->GetInterfaceForDevice(extDev1_direct.Get(0));
    staticExt1->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),
                                ext1Interfaces_direct.GetAddress(1), ifaceIndex);

    // E1 → A1 detour
    ifaceIndex = ipv4_ext1->GetInterfaceForDevice(extDev1_direct.Get(0));
    staticExt1->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),
                              ext1Interfaces_direct.GetAddress(1), ifaceIndex);
    // ifaceIndex = ipv4_ext1->GetInterfaceForDevice(extDev1_detour.Get(0));
    // staticExt1->AddNetworkRouteTo(ext0Interfaces.GetAddress(0), Ipv4Mask("255.255.255.0"),ext1Interfaces_detour.GetAddress(1), ifaceIndex);

    // E2 : route par défaut vers D2 uniquement.
    // Le trafic parasite de E2 ne sortira que d'un saut backbone (D2→extraDetour[0] ou D2→D1).
    ifaceIndex = ipv4_ext2->GetInterfaceForDevice(extDev2.Get(0));
    staticExt2->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), ext2Interfaces.GetAddress(1), ifaceIndex);
    // staticExt2->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),ext2Interfaces.GetAddress(1), ifaceIndex);
    // staticExt2->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),ext2Interfaces.GetAddress(1), ifaceIndex);

    // Parasite routing – chaque nœud parasite n'a qu'une route par défaut vers son routeur adjacent.
    // Le trafic sortira sur l'interface forward du routeur adjacent et se terminera au saut suivant :
    // pas d'accumulation multi-sauts.
    if (numExtraRouters > 0 )
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            Ptr<Node> parasite = parasiteNodes.Get(i);
            Ipv4Address nextHop = parasiteIfaces[i].GetAddress(1); // vers son routeur extraRouters[i] uniquement
            Ptr<Ipv4> ipv4_para = parasite->GetObject<Ipv4>();
            ifaceIndex = ipv4_para->GetInterfaceForDevice(parasiteDevices[i].Get(0));
            Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_para);
            // Route par défaut : tout sort vers le routeur adjacent, qui gère le dernier saut localement
            routing->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHop, ifaceIndex);
            // routing->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
            // routing->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
        }
    }

    for (uint32_t i = 0; i < numExtraDetour; ++i)
    {
        Ptr<Node> parasite = parasiteDetour.Get(i);
        Ipv4Address nextHop = detourParasiteIfaces[i].GetAddress(1); // vers son routeur extraDetour[i] uniquement
        Ptr<Ipv4> ipv4_para = parasite->GetObject<Ipv4>();
        ifaceIndex = ipv4_para->GetInterfaceForDevice(detourParasiteDevices[i].Get(0));
        Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_para);
        // Route par défaut
        routing->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHop, ifaceIndex);
        // routing->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
        // routing->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
    }


    std::string animFile = prefixfile + namefile +"animation.xml"; // Name of file for animation output 
    // Create the animation object and configure for specified output
    AnimationInterface anim(animFile);
    anim.EnablePacketMetadata(true); // Optional
    

    std::ostringstream oss_direct;
    (lan1_direct.GetAddress(0)).Print(oss_direct);
    anim.AddSourceDestination(0, oss_direct.str());

    std::ostringstream oss_detour;
    (lan1_detour.GetAddress(0)).Print(oss_detour);
    anim.AddSourceDestination(0, oss_detour.str());


    anim.EnableIpv4L3ProtocolCounters(Seconds(startTime), Seconds(stopTime)); // Optional
    anim.EnableQueueCounters(Seconds(startTime), Seconds(stopTime)); // Optional

    int latency_direct_int = (int)latency_direct_float +(2000000000/(numExtraRouters + 5)); // Convert to milliseconds for animation
    int x = 1;
    int y = 850000000 ;//latency_direct_int;
    int y_parasite = y + latency_direct_int;
    int z = 0;
    anim.SetConstantPosition (accessRouters.Get(0),x, y, z);
    anim.UpdateNodeDescription(accessRouters.Get(0), "A0");
    if (numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            x = x+latency_direct_int;
            anim.SetConstantPosition(extraRouters.Get(i),x, y, z);
            int id = i + 2;
            anim.UpdateNodeDescription(extraRouters.Get(i), "A"+std::to_string(id));
            anim.SetConstantPosition(parasiteNodes.Get(i),x, y_parasite, z);
            anim.UpdateNodeDescription(parasiteNodes.Get(i), "P"+std::to_string(id));
        }
    }
    x = x+ latency_direct_int;

    anim.SetConstantPosition (distRouters.Get(0),x, y, z);
    anim.UpdateNodeDescription(distRouters.Get(0), "D0");
    int x0 = x;
    int y0 = y;
    anim.SetConstantPosition (external0Nodes.Get(0),x, y_parasite, z);
    anim.UpdateNodeDescription(external0Nodes.Get(0), "E0");
    x= x+latency_direct_int;
    int x1 = x;
    int y1 = y;
    anim.SetConstantPosition (distRouters.Get(1),x, y, z);
    anim.UpdateNodeDescription(distRouters.Get(1), "D1");
    anim.SetConstantPosition (external1Nodes.Get(0),x, y_parasite, z);
    anim.UpdateNodeDescription(external1Nodes.Get(0), "E1");
    x = x+ latency_direct_int;
    anim.SetConstantPosition (accessRouters.Get(1),x, y, z);
    anim.UpdateNodeDescription(accessRouters.Get(1), "A1");

    int n = numExtraDetour + 3;
    auto points = GenerateSemiCirclePointsFromDiameter(x0, y0, x1, y1, n);

    anim.SetConstantPosition (distRouters.Get(2),points[points.size()-2].x, points[points.size()-2].y, z); // positioner D2
    anim.UpdateNodeDescription(distRouters.Get(2), "D2");
    anim.SetConstantPosition (external2Nodes.Get(0),points[points.size()-2].x, points[points.size()-2].y + latency_direct_int, z);
    anim.UpdateNodeDescription(external2Nodes.Get(0), "E2");
    for (int i = static_cast<int>(points.size())-3; i > 0; --i) {
        int id = static_cast<int>(points.size()) -i;
        int j = id-3;
        anim.SetConstantPosition (extraDetour.Get(j),points[i].x, points[i].y, z);
        anim.UpdateNodeDescription(extraDetour.Get(j), "D"+std::to_string(id));
        anim.SetConstantPosition (parasiteDetour.Get(j),points[i].x, points[i].y+latency_direct_int, z);
        anim.UpdateNodeDescription(parasiteDetour.Get(j), "E"+std::to_string(id));
    }





    // Populate global routing (must come after static routes)
    Ipv4GlobalRoutingHelper::PopulateRoutingTables();

    // SetupPing(accessRouters.Get(0), lan1_direct.GetAddress(0), 0, stopTime/2);
    // SetupPing(accessRouters.Get(0), lan1_detour.GetAddress(0), 0, stopTime/2);

    // if (numExtraRouters > 0)
    // {
    //     SetupPing(extraRouters.Get(0), lan1_direct.GetAddress(0), 0, stopTime);
    //     SetupPing(parasiteNodes.Get(1), ext1Interfaces_detour.GetAddress(0), 0, stopTime/2);
    // }
    // if (numExtraDetour > 0)
    // {
    //     SetupPing(extraDetour.Get(0), lan1_detour.GetAddress(0), 0, stopTime/2);
    //     SetupPing(parasiteDetour.Get(2), ext1Interfaces_detour.GetAddress(0), 0, stopTime/2);
    // }
    



    // 
    //SetupPing(external0Nodes.Get(0), ext1Interfaces_detour.GetAddress(0), 0, stopTime/2);

    Ptr<OutputStreamWrapper> stream = Create<OutputStreamWrapper>(&std::cout);

    for (uint32_t i = 0; i < accessRouters.GetN(); ++i)
    {
        Ptr<Ipv4> ipv4 = accessRouters.Get(i)->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> staticRoutingacces = staticRouting.GetStaticRouting(ipv4);
        std::cout << "Routing table for access node " << i << ":\n";
        staticRoutingacces->PrintRoutingTable(stream);
    }
    for (uint32_t i = 0; i < distRouters.GetN(); ++i)
    {
        Ptr<Ipv4> ipv4 = distRouters.Get(i)->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> staticRoutingdist = staticRouting.GetStaticRouting(ipv4);
        std::cout << "Routing table for dist node " << i << ":\n";
        staticRoutingdist->PrintRoutingTable(stream);
    }
    for (uint32_t i = 0; i < external0Nodes.GetN(); ++i)
    {
        Ptr<Ipv4> ipv4 = external0Nodes.Get(i)->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> staticRoutingext0 = staticRouting.GetStaticRouting(ipv4);
        std::cout << "Routing table for ext0 node " << i << ":\n";
        staticRoutingext0->PrintRoutingTable(stream);
    }
    for (uint32_t i = 0; i < external1Nodes.GetN(); ++i)
    {
        Ptr<Ipv4> ipv4 = external1Nodes.Get(i)->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> staticRoutingext1 = staticRouting.GetStaticRouting(ipv4);
        std::cout << "Routing table for ext1 node " << i << ":\n";
        staticRoutingext1->PrintRoutingTable(stream);
    }
    for (uint32_t i = 0; i < external2Nodes.GetN(); ++i)
    {
        Ptr<Ipv4> ipv4 = external2Nodes.Get(i)->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> staticRoutingext2 = staticRouting.GetStaticRouting(ipv4);
        std::cout << "Routing table for ext2 node " << i << ":\n";
        staticRoutingext2->PrintRoutingTable(stream);
    }

    if (numExtraRouters> 0 )
    {
        for (uint32_t i = 0; i < extraRouters.GetN(); ++i)
        {
            Ptr<Ipv4> ipv4 = extraRouters.Get(i)->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> staticRoutingextra = staticRouting.GetStaticRouting(ipv4);
            std::cout << "Routing table for extra node " << i << ":\n";
            staticRoutingextra->PrintRoutingTable(stream);
        }
        for (uint32_t i = 0; i < parasiteNodes.GetN(); ++i)
        {
            Ptr<Ipv4> ipv4 = parasiteNodes.Get(i)->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> staticRoutingPara = staticRouting.GetStaticRouting(ipv4);
            std::cout << "Routing table for parasite node " << i << ":\n";
            staticRoutingPara->PrintRoutingTable(stream);
        }
    }

    if (numExtraDetour> 0 )
    {
        for (uint32_t i = 0; i < extraDetour.GetN(); ++i)
        {
            Ptr<Ipv4> ipv4 = extraDetour.Get(i)->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> staticRoutingextra = staticRouting.GetStaticRouting(ipv4);
            std::cout << "Routing table for detour extra node " << i << ":\n";
            staticRoutingextra->PrintRoutingTable(stream);
        }
        for (uint32_t i = 0; i < parasiteDetour.GetN(); ++i)
        {
            Ptr<Ipv4> ipv4 = parasiteDetour.Get(i)->GetObject<Ipv4>();
            Ptr<Ipv4StaticRouting> staticRoutingPara = staticRouting.GetStaticRouting(ipv4);
            std::cout << "Routing table for detour parasite node " << i << ":\n";
            staticRoutingPara->PrintRoutingTable(stream);
        }
    }



    // Traceroute for detour path
    V4TraceRouteHelper traceroute_detour(lan1_detour.GetAddress(0)); // size - 1
    traceroute_detour.SetAttribute("Verbose", BooleanValue(true));
    ApplicationContainer p_detour = traceroute_detour.Install(accessRouters.Get(0));

    // Used when we wish to dump the traceroute results into a file
    Ptr<OutputStreamWrapper> printstrm_detour = Create<OutputStreamWrapper> (prefixfile +namefile +"traceroute_detour.txt", std::ios::out);
    traceroute_detour.PrintTraceRouteAt(accessRouters.Get(0),printstrm_detour);

    p_detour.Start(Seconds(0));
    p_detour.Stop(Seconds(stopTime/2) - Seconds(0.001));

    // Traceroute for direct path
    V4TraceRouteHelper traceroute_direct(lan1_direct.GetAddress(0)); // size - 1
    traceroute_direct.SetAttribute("Verbose", BooleanValue(true));
    ApplicationContainer p_direct = traceroute_direct.Install(accessRouters.Get(0));

    // Used when we wish to dump the traceroute results into a file
    Ptr<OutputStreamWrapper> printstrm_direct = Create<OutputStreamWrapper> (prefixfile +namefile +"traceroute_direct.txt", std::ios::out);
    traceroute_direct.PrintTraceRouteAt(accessRouters.Get(0), printstrm_direct);

    p_direct.Start(Seconds(stopTime/2));
    p_direct.Stop(Seconds(stopTime) - Seconds(0.001));









    // Tester avec une application simple
    uint32_t numFlows_direct = 1; // nombre de flux 
    uint32_t numFlows_detour = 1; // nombre de flux 
    uint32_t numFlowsExt = 1; // nombre de flux parasite
    uint16_t port = 9;  // Port des flux UDP
    
    stopTime = stopTime + numFlows_detour + numFlows_direct + numFlowsExt;

    

    // Ptr<UniformRandomVariable> uv = CreateObject<UniformRandomVariable> ();
    // uv->SetAttribute ("Min", DoubleValue (0.0));
    // uv->SetAttribute ("Max", DoubleValue (numFlowsExt));
    
    Ptr<ExponentialRandomVariable> exp_var = CreateObject<ExponentialRandomVariable> ();
    exp_var->SetAttribute ("Mean", DoubleValue (exp_mean));
    

    Ptr<ExponentialRandomVariable> exp_var_para = CreateObject<ExponentialRandomVariable> ();
    exp_var_para->SetAttribute ("Mean", DoubleValue (exp_mean_para));
    // double exp_var = ns3::ExponentialVariable::GetSingleValue (exp_mean);

    std::string onVariable = "ns3::ConstantRandomVariable[Constant=" + std::to_string(exp_mean)+ "]"; //A RandomVariableStream used to pick the duration of the 'On' state.
    std::string offVariable = "ns3::ExponentialRandomVariable[Mean=" + std::to_string(exp_mean)+ "]"; 
    //std::string offVariable = "ns3::ConstantRandomVariable[Constant=0]";

    //std::string onVariable = "ns3::ZipfRandomVariable[Alpha=2]"
    std::string onVariablePara = "ns3::ConstantRandomVariable[Constant=" + std::to_string(exp_mean_para)+ "]"; //1000
    //std::string offVariablePara = "ns3::ConstantRandomVariable[Constant=0]";
    std::string offVariablePara = "ns3::ExponentialRandomVariable[Mean=" + std::to_string(exp_mean_para)+ "]";
    






// Flow (Direct Path)
    for (uint32_t i = 0; i < numFlows_direct; ++i) {  // numFlows flux

        Ipv4Address dst = lan1_direct.GetAddress(0);
        Address sinkAddressDirect(InetSocketAddress(dst, port + i));
        PacketSinkHelper sinkDirect(socketType, sinkAddressDirect);
        ApplicationContainer sinkAppsDirect = sinkDirect.Install(accessRouters.Get(1));
        sinkAppsDirect.Start(Seconds(startTime));
        sinkAppsDirect.Stop(Seconds(stopTime));

        OnOffHelper clientDirect(socketType, sinkAddressDirect);
        //clientDirect.SetConstantRate(DataRate(dataRateAccess), packetSize);
        clientDirect.SetAttribute("OnTime", StringValue(onVariable));
        clientDirect.SetAttribute("OffTime", StringValue(offVariable));
        clientDirect.SetAttribute("DataRate", DataRateValue(DataRate(dataRateAccess))); //bit/s
        clientDirect.SetAttribute("PacketSize", UintegerValue(packetSize));
        //
        ApplicationContainer clientAppsDirect = clientDirect.Install(accessRouters.Get(0));
        double value = exp_var->GetValue ();
        clientAppsDirect.Start(Seconds(startTime + i/10+ value));
        clientAppsDirect.Stop(Seconds(stopTime));
    }


    // Flow (Detour Path)
    for (uint32_t i = 0; i < numFlows_detour; ++i) {  // numFlowsTCP flux

        //Sink on destination (accessRouter 1)
        Address sinkAddressDetour(InetSocketAddress(lan1_detour.GetAddress(0), port + numFlows_direct +i));
        PacketSinkHelper SinkDetour(socketType, sinkAddressDetour);
        ApplicationContainer SinkApp = SinkDetour.Install(accessRouters.Get(1));
        SinkApp.Start(Seconds(startTime));
        SinkApp.Stop(Seconds(stopTime));

        // TCP Source on source (accessRouter 0)
        OnOffHelper ClientDetour(socketType, sinkAddressDetour);
        ClientDetour.SetAttribute("OnTime", StringValue(onVariable));
        ClientDetour.SetAttribute("OffTime", StringValue(offVariable));
        ClientDetour.SetAttribute("DataRate", StringValue(dataRateAccess));
        ClientDetour.SetAttribute("PacketSize", UintegerValue(packetSize));
        //
        //ClientDetour.SetConstantRate(DataRate(dataRateAccess), packetSize); // packetSize in bytes



        ApplicationContainer AppDetour = ClientDetour.Install(accessRouters.Get(0));
        double value = exp_var->GetValue ();
        AppDetour.Start(Seconds(startTime + i/10 + value));
        AppDetour.Stop(Seconds(stopTime));
    }

    // // Lancer du trafic parasite direct
    // // On OFF parasite
    // std::cout << "numFlow: " << numFlowsExt << std::endl;

    // for (uint32_t i = 0; i < numFlowsExt; ++i) {
    //     //Sink on destination (accessRouter 1)
    //     Address sinkAddressExt(InetSocketAddress(ext1Interfaces_direct.GetAddress(0), port + numFlows_direct + numFlows_detour +i));
    //     PacketSinkHelper SinkDetour(socketType_Ext, sinkAddressExt);
    //     ApplicationContainer SinkApp = SinkDetour.Install(external1Nodes.Get(0));
    //     SinkApp.Start(Seconds(startTime ));
    //     SinkApp.Stop(Seconds(stopTime + 1.1));

    //     // Source on source 
    //     OnOffHelper ClientDetour(socketType_Ext, sinkAddressExt);
    //     ClientDetour.SetAttribute("OnTime", StringValue(onVariablePara));
    //     ClientDetour.SetAttribute("OffTime", StringValue(offVariablePara));
    //     ClientDetour.SetAttribute("DataRate", StringValue(dataRateExt_D0));
    //     ClientDetour.SetAttribute("PacketSize", UintegerValue(packetSize));
    //     //
    //     //ClientDetour.SetConstantRate(DataRate(dataRateExt), packetSize); 



    //     ApplicationContainer AppDetour = ClientDetour.Install(external0Nodes.Get(0));
    //     AppDetour.Start(Seconds(startTime ));
    //     AppDetour.Stop(Seconds(stopTime ));
    // }

    // // Lancer du trafic parasite detour
    // std::cout << "numFlow: " << numFlowsExt << std::endl;

    // for (uint32_t i = 0; i < numFlowsExt; ++i) {    
    //     Address sinkAddressExt(InetSocketAddress(ext1Interfaces_detour.GetAddress(0), port + numFlows_direct + numFlows_detour + numFlowsExt+i));
    //     PacketSinkHelper SinkDetour(socketType_Ext, sinkAddressExt);
    //     ApplicationContainer SinkApp = SinkDetour.Install(external1Nodes.Get(0));
    //     SinkApp.Start(Seconds(startTime ));
    //     SinkApp.Stop(Seconds(stopTime + 1.1));

    //     // Source on source 
    //     OnOffHelper ClientDetour(socketType_Ext, sinkAddressExt);
    //     ClientDetour.SetAttribute("OnTime", StringValue(onVariablePara));
    //     ClientDetour.SetAttribute("OffTime", StringValue(offVariablePara));
    //     ClientDetour.SetAttribute("DataRate", StringValue(dataRateExt));
    //     ClientDetour.SetAttribute("PacketSize", UintegerValue(packetSize));
    //     //
    //     //ClientDetour.SetConstantRate(DataRate(dataRateExt), packetSize);


    //     ApplicationContainer AppDetour = ClientDetour.Install(external0Nodes.Get(0));
    //     AppDetour.Start(Seconds(startTime ));
    //     AppDetour.Stop(Seconds(stopTime ));
    // }

    // // paraisate from D2
    // for (uint32_t i = 0; i < numFlowsExt; ++i) {    
    //     //Sink on destination (accessRouter 1)
    //     Address sinkAddressExt(InetSocketAddress(ext1Interfaces_direct.GetAddress(0), port + numFlows_direct + numFlows_detour + 2*numFlowsExt + i));
    //     PacketSinkHelper SinkDetour(socketType_Ext, sinkAddressExt);
    //     ApplicationContainer SinkApp = SinkDetour.Install(external1Nodes.Get(0));
    //     SinkApp.Start(Seconds(startTime ));
    //     SinkApp.Stop(Seconds(stopTime + 1.1));

    //     // Source on source 
    //     OnOffHelper ClientDetour(socketType_Ext, sinkAddressExt);
    //     ClientDetour.SetAttribute("OnTime", StringValue(onVariablePara));
    //     ClientDetour.SetAttribute("OffTime", StringValue(offVariablePara));
    //     ClientDetour.SetAttribute("DataRate", StringValue(dataRateExt));
    //     ClientDetour.SetAttribute("PacketSize", UintegerValue(packetSize));
    //     //
    //     //ClientDetour.SetConstantRate(DataRate(dataRateExt), packetSize); 

    //     ApplicationContainer AppDetour = ClientDetour.Install(external2Nodes.Get(0));
    //     AppDetour.Start(Seconds(startTime ));
    //     AppDetour.Stop(Seconds(stopTime));
    // }

    // if (numExtraRouters > 0)
    // {
    //     Address sinkAddress = InetSocketAddress(ext1Interfaces_direct.GetAddress(0), 9999);

    //     for (uint32_t i = 0; i < numExtraRouters; ++i)
    //     {
    //         if (i%2 == 0) 
    //         {
    //             sinkAddress = InetSocketAddress(ext1Interfaces_detour.GetAddress(0), 9999);
    //         } else {
    //             sinkAddress = InetSocketAddress(ext1Interfaces_direct.GetAddress(0), 9999);
    //         }
    //         OnOffHelper onoff(socketType_Ext, sinkAddress);
    //         onoff.SetAttribute("DataRate", StringValue(dataRateExt));
    //         onoff.SetAttribute("PacketSize", UintegerValue(packetSize));
    //         onoff.SetAttribute("StartTime", TimeValue(Seconds(startTime)));
    //         onoff.SetAttribute("StopTime", TimeValue(Seconds(stopTime)));
    //         onoff.Install(parasiteNodes.Get(i));
    //     }

    //     // Sink sur A1
    //     PacketSinkHelper sink(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), 9999));
    //     sink.Install(external1Nodes.Get(0));
    // }

    // if (numExtraDetour > 0)
    // {
    //     Address sinkAddress = InetSocketAddress(ext1Interfaces_direct.GetAddress(0), 8888);

    //     for (uint32_t i = 0; i < numExtraDetour; ++i)
    //     {
    //         if (i%2 != 0) 
    //         {
    //             sinkAddress = InetSocketAddress(ext1Interfaces_detour.GetAddress(0), 9999);
    //         } else {
    //             sinkAddress = InetSocketAddress(ext1Interfaces_direct.GetAddress(0), 9999);
    //         }
    //         OnOffHelper onoff(socketType_Ext, sinkAddress);
    //         onoff.SetAttribute("DataRate", StringValue(dataRateExt));
    //         onoff.SetAttribute("PacketSize", UintegerValue(packetSize));
    //         onoff.SetAttribute("StartTime", TimeValue(Seconds(startTime)));
    //         onoff.SetAttribute("StopTime", TimeValue(Seconds(stopTime)));
    //         onoff.Install(parasiteDetour.Get(i));
    //     }

    //     // Sink sur A1
    //     PacketSinkHelper sink(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), 8888));
    //     sink.Install(external1Nodes.Get(0));
    // }


    // === PARASITES E0 et E2 et E1 : trafic local 1 saut ===
    // Principe identique aux parasiteNodes/Detour : le trafic s'arrête au premier routeur backbone
    // adjacent, stressant exactement un lien partagé avec les flux directs/détournés.

    // Parasite E0 → D1 (direct, 1 saut : D0 → D1 via backbone01)
    // Impact : charge la file de sortie D0→D1, partagée avec le flux direct.
    std::cout << "numFlow parasite E0 direct (1 saut D0->D1): " << numFlowsExt << std::endl;
    {
        const uint16_t portE0direct = 6001 + port + numFlows_direct + numFlows_detour;
        // iface01.GetAddress(1) = IP de D1 sur le lien backbone01
        Address sinkAddr(InetSocketAddress(iface01.GetAddress(1), portE0direct));
        PacketSinkHelper sinkHelper(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), portE0direct));
        ApplicationContainer sinkApp = sinkHelper.Install(distRouters.Get(1)); // D1 — terminus local
        sinkApp.Start(Seconds(startTime));
        sinkApp.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            OnOffHelper client(socketType_Ext, sinkAddr);
            client.SetAttribute("OnTime",  StringValue(onVariablePara));
            client.SetAttribute("OffTime", StringValue(offVariablePara));
            client.SetAttribute("DataRate", StringValue(dataRateExt));
            client.SetAttribute("PacketSize", UintegerValue(packetSize));
            ApplicationContainer app = client.Install(external0Nodes.Get(0));
            app.Start(Seconds(startTime));
            app.Stop(Seconds(stopTime));
        }
    }

    // Parasite E0 → D2 (détour, 1 saut : D0 → D2 via backbone02)
    // Impact : charge la file de sortie D0→D2, partagée avec le flux détourné.
    std::cout << "numFlow parasite E0 detour (1 saut D0->D2): " << numFlowsExt << std::endl;
    {
        const uint16_t portE0detour = 6002 + port + numFlows_direct + numFlows_detour;
        // iface02.GetAddress(1) = IP de D2 sur le lien backbone02
        Address sinkAddr(InetSocketAddress(iface02.GetAddress(1), portE0detour));
        PacketSinkHelper sinkHelper(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), portE0detour));
        ApplicationContainer sinkApp = sinkHelper.Install(distRouters.Get(2)); // D2 — terminus local
        sinkApp.Start(Seconds(startTime));
        sinkApp.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            OnOffHelper client(socketType_Ext, sinkAddr);
            client.SetAttribute("OnTime",  StringValue(onVariablePara));
            client.SetAttribute("OffTime", StringValue(offVariablePara));
            client.SetAttribute("DataRate", StringValue(dataRateExt));
            client.SetAttribute("PacketSize", UintegerValue(packetSize));
            ApplicationContainer app = client.Install(external0Nodes.Get(0));
            app.Start(Seconds(startTime));
            app.Stop(Seconds(stopTime));
        }
    }

    // Parasite E2 → premier saut de la chaîne détour depuis D2
    // Si numExtraDetour > 0 : D2 → extraDetour[0]  (detourChainIfaces[0].GetAddress(1))
    // Si numExtraDetour = 0 : D2 → D1              (backbone21, detourChainIfaces[0].GetAddress(1))
    // Impact : charge la file de sortie D2→premier_nœud_détour, partagée avec le flux détourné.
    std::cout << "numFlow parasite E2 (1 saut D2->suivant): " << numFlowsExt << std::endl;
    {
        const uint16_t portE2 = 6003 + port + numFlows_direct + numFlows_detour;
        // detourChainIfaces[0] = lien D2 ↔ extraDetour[0] (ou D1 si pas d'extra)
        // GetAddress(1) = IP du nœud à droite du lien = premier saut depuis D2
        Ipv4Address dstIP = detourChainIfaces[0].GetAddress(1);
        Ptr<Node> sinkNode = (numExtraDetour > 0) ? extraDetour.Get(0) : distRouters.Get(1);
        Address sinkAddr(InetSocketAddress(dstIP, portE2));
        PacketSinkHelper sinkHelper(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), portE2));
        ApplicationContainer sinkApp = sinkHelper.Install(sinkNode); // terminus local
        sinkApp.Start(Seconds(startTime));
        sinkApp.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            OnOffHelper client(socketType_Ext, sinkAddr);
            client.SetAttribute("OnTime",  StringValue(onVariablePara));
            client.SetAttribute("OffTime", StringValue(offVariablePara));
            client.SetAttribute("DataRate", StringValue(dataRateExt));
            client.SetAttribute("PacketSize", UintegerValue(packetSize));
            ApplicationContainer app = client.Install(external2Nodes.Get(0));
            app.Start(Seconds(startTime));
            app.Stop(Seconds(stopTime));
        }
    }

    // Parasite E1 → A1 (direct, 1 saut : D1 → A1 via distDevices1_direct)
    // Impact : charge la file de sortie D1 → A1, partagée avec le flux direct.
    std::cout << "numFlow parasite E1 detour (1 saut D1 → A1): " << numFlowsExt << std::endl;
    {
        const uint16_t portE1direct = 6004 + port + numFlows_direct + numFlows_detour;
        // lan1_direct.GetAddress(0) = IP de A1 sur le lien distDevice1_direct
        Address sinkAddr(InetSocketAddress(lan1_direct.GetAddress(0), portE1direct));
        PacketSinkHelper sinkHelper(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), portE1direct));
        ApplicationContainer sinkApp = sinkHelper.Install(accessRouters.Get(1)); // A1 — terminus local
        sinkApp.Start(Seconds(startTime));
        sinkApp.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            OnOffHelper client(socketType_Ext, sinkAddr);
            client.SetAttribute("OnTime",  StringValue(onVariablePara));
            client.SetAttribute("OffTime", StringValue(offVariablePara));
            client.SetAttribute("DataRate", StringValue(dataRateExt));
            client.SetAttribute("PacketSize", UintegerValue(packetSize));
            ApplicationContainer app = client.Install(external1Nodes.Get(0));
            app.Start(Seconds(startTime));
            app.Stop(Seconds(stopTime));
        }
    }
    // Parasite E1 → A1 (détour, 1 saut : D1 → A1 via /distDevices1_detour)
    // Impact : charge la file de sortie D1 → A1, partagée avec le flux détourné.
    std::cout << "numFlow parasite E1 detour (1 saut D1 → A1): " << numFlowsExt << std::endl;
    {
        const uint16_t portE1detour = 6005 + port + numFlows_direct + numFlows_detour;
        // lan1_detour.GetAddress(0) = IP de A1 sur le lien distDevice1_ddetour
        Address sinkAddr(InetSocketAddress(lan1_detour.GetAddress(0), portE1detour));
        PacketSinkHelper sinkHelper(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), portE1detour));
        ApplicationContainer sinkApp = sinkHelper.Install(accessRouters.Get(1)); // A1 — terminus local
        sinkApp.Start(Seconds(startTime));
        sinkApp.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            OnOffHelper client(socketType_Ext, sinkAddr);
            client.SetAttribute("OnTime",  StringValue(onVariablePara));
            client.SetAttribute("OffTime", StringValue(offVariablePara));
            client.SetAttribute("DataRate", StringValue(dataRateExt));
            client.SetAttribute("PacketSize", UintegerValue(packetSize));
            ApplicationContainer app = client.Install(external1Nodes.Get(0));
            app.Start(Seconds(startTime));
            app.Stop(Seconds(stopTime));
        }
    }

    
    // Trafic parasite local : chaque parasiteNodes[i] envoie vers le routeur suivant dans la chaîne
    // (extraRouters[i+1] ou D0 pour le dernier). Le trafic ne traverse qu'UN SEUL lien backbone,
    // celui partagé avec les flux directs/détournés. Pas d'accumulation de saut en saut.
    const uint16_t parasite_local_port_base = 7000+ port + numFlows_direct + numFlows_detour;

    if (numExtraRouters > 0)
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            // IP du routeur suivant sur le lien chaîne i+1 (= right side de chainIfaces[i+1])
            // chainIfaces[i+1] = lien extraRouters[i] ↔ extraRouters[i+1] (ou D0 si i == dernier)
            Ipv4Address nextRouterIP = chainIfaces[i + 1].GetAddress(1);
            uint16_t localPort = parasite_local_port_base + static_cast<uint16_t>(i);
            Address sinkAddress(InetSocketAddress(nextRouterIP, localPort));

            // Sink local sur le routeur suivant – termine le trafic en exactement 1 saut backbone
            Ptr<Node> sinkNode = (i < numExtraRouters - 1)
                                 ? extraRouters.Get(i + 1)
                                 : distRouters.Get(0); // D0 pour le dernier
            PacketSinkHelper localSink(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), localPort));
            ApplicationContainer localSinkApp = localSink.Install(sinkNode);
            localSinkApp.Start(Seconds(startTime));
            localSinkApp.Stop(Seconds(stopTime + 2));

            // Source parasite : même profil On/Off que le parasite global
            OnOffHelper onoff(socketType_Ext, sinkAddress);
            onoff.SetAttribute("OnTime",  StringValue(onVariablePara));
            onoff.SetAttribute("OffTime", StringValue(offVariablePara));
            onoff.SetAttribute("DataRate", StringValue(dataRateExt));
            onoff.SetAttribute("PacketSize", UintegerValue(packetSize));
            onoff.SetAttribute("StartTime", TimeValue(Seconds(startTime)));
            onoff.SetAttribute("StopTime",  TimeValue(Seconds(stopTime)));
            onoff.Install(parasiteNodes.Get(i));
        }
    }


if (numExtraDetour > 0)
    {
        for (uint32_t i = 0; i < numExtraDetour; ++i)
        {
            // IP du nœud suivant sur le lien détour i+1 (= right side de detourChainIfaces[i+1])
            // detourChainIfaces[i+1] = lien extraDetour[i] ↔ extraDetour[i+1] (ou D1 si i == dernier)
            Ipv4Address nextRouterIP = detourChainIfaces[i + 1].GetAddress(1);
            uint16_t localPort = parasite_local_port_base
                                 + static_cast<uint16_t>(numExtraRouters)
                                 + static_cast<uint16_t>(i);
            Address sinkAddress(InetSocketAddress(nextRouterIP, localPort));

            // Sink local sur le routeur suivant
            Ptr<Node> sinkNode = (i < numExtraDetour - 1)
                                 ? extraDetour.Get(i + 1)
                                 : distRouters.Get(1); // D1 pour le dernier
            PacketSinkHelper localSink(socketType_Ext, InetSocketAddress(Ipv4Address::GetAny(), localPort));
            ApplicationContainer localSinkApp = localSink.Install(sinkNode);
            localSinkApp.Start(Seconds(startTime));
            localSinkApp.Stop(Seconds(stopTime + 2));

            // Source parasite détour
            OnOffHelper onoff(socketType_Ext, sinkAddress);
            onoff.SetAttribute("OnTime",  StringValue(onVariablePara));
            onoff.SetAttribute("OffTime", StringValue(offVariablePara));
            onoff.SetAttribute("DataRate", StringValue(dataRateExt));
            onoff.SetAttribute("PacketSize", UintegerValue(packetSize));
            onoff.SetAttribute("StartTime", TimeValue(Seconds(startTime)));
            onoff.SetAttribute("StopTime",  TimeValue(Seconds(stopTime)));
            onoff.Install(parasiteDetour.Get(i));
        }
    }

    

    




























    
    // === TRACE CALLBACKS ===

    // Ask for ASCII and pcap traces of network traffic
    //
    if (numExtraRouters > 0)
    {
        distLink.EnablePcap(prefixfile + namefile + "trace-access0-access_access0", chainDevices[0].Get(0), true);
        distLink.EnablePcap(prefixfile + namefile + "trace-access-dist0_dist0", chainDevices[numExtraRouters].Get(1), true);
    }else{
        distLink.EnablePcap(prefixfile + namefile + "trace-access0-access_access0", distDevices0_direct.Get(0), true);
        distLink.EnablePcap(prefixfile + namefile + "trace-access-dist0_dist0", distDevices0_direct.Get(1), true);
    }
    

    backbone_direct.EnablePcap(prefixfile + namefile + "trace-dist0-dist1_dist0", backbone01.Get(0), true);
    backbone_direct.EnablePcap(prefixfile + namefile + "trace-dist0-dist1_dist1", backbone01.Get(1), true);
    
    backbone_detour.EnablePcap(prefixfile + namefile + "trace-dist2-dist1_dist1", backbone21.Get(1), true);
    
    backbone_detour.EnablePcap(prefixfile + namefile + "trace-dist0-dist2_dist0", backbone02.Get(0), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-direct_access1", distDevices1_direct.Get(0), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-direct_dist1", distDevices1_direct.Get(1), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-detour_access1", distDevices1_detour.Get(0), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-detour_dist1", distDevices1_detour.Get(1), true);
    

    if (numExtraRouters > 0)
    {
        distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", chainDevices[0]);
        distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", chainDevices[numExtraRouters]);
    } else {
        distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", distDevices0_direct);
    }

    distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", distDevices1_direct);
    distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", distDevices1_detour);

    backbone_direct.EnableAscii(prefixfile + namefile + "ninth-backbone", backbone01);
    backbone_detour.EnableAscii(prefixfile + namefile + "ninth-backbone", backbone02);

    if (numExtraDetour > 0)
    {
        backbone_detour.EnableAscii(prefixfile + namefile + "ninth-backbone", detourChainDevices[0]);
        distLink.EnableAscii(prefixfile + namefile + "ninth-backbone", detourChainDevices[numExtraDetour]);
    } else {
        backbone_detour.EnableAscii(prefixfile + namefile + "ninth-backbone", backbone21);
    }

    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev0);
    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev1_direct);
    //extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev1_detour);
    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev2);

    FlowMonitorHelper flowmonHelper;
    Ptr<FlowMonitor> monitor;
    if (enableFlowMonitor)
    {
        monitor = flowmonHelper.InstallAll();
    }

    std::cout << "stopTime:"<< stopTime << std::endl;
    Simulator::Stop(Seconds(stopTime + 400));
    Simulator::Run();
    std::cout << "Simulation ended at " << Simulator::Now().GetSeconds() << "s" << std::endl;


    // Ptr<Ipv4FlowClassifier> classifier;
    // if (enableFlowMonitor)
    // {
    //     monitor -> CheckForLostPackets();
    //     monitor -> SerializeToXmlFile(prefixfile + namefile + "ninth.flowmon", true, true);
    //     classifier = DynamicCast<Ipv4FlowClassifier>(flowmonHelper.GetClassifier());
    // std::map<FlowId, FlowMonitor::FlowStats> stats = monitor->GetFlowStats();
    // std::cout << std::endl << "*** Flow monitor statistics ***" << std::endl;
    // std::cout << "  Tx Packets/Bytes:   " << stats[1].txPackets << " / " << stats[1].txBytes
    //           << std::endl;
    // std::cout << "  Offered Load: "
    //           << stats[1].txBytes * 8.0 /
    //                  (stats[1].timeLastTxPacket.GetSeconds() -
    //                   stats[1].timeFirstTxPacket.GetSeconds()) /
    //                  1000000
    //           << " Mbps" << std::endl;
    // std::cout << "  Rx Packets/Bytes:   " << stats[1].rxPackets << " / " << stats[1].rxBytes
    //           << std::endl;
    //           uint32_t packetsDroppedByNetDevice = 0;
    //           uint64_t bytesDroppedByNetDevice = 0;
    //           if (stats[1].packetsDropped.size() > Ipv4FlowProbe::DROP_QUEUE)
    //           {
    //               packetsDroppedByNetDevice = stats[1].packetsDropped[Ipv4FlowProbe::DROP_QUEUE];
    //               bytesDroppedByNetDevice = stats[1].bytesDropped[Ipv4FlowProbe::DROP_QUEUE];
    //           }
    //           std::cout << "  Packets/Bytes Dropped by NetDevice:   " << packetsDroppedByNetDevice << " / "
    //                     << bytesDroppedByNetDevice << std::endl;
    //           std::cout << "  Throughput: "
    //                     << stats[1].rxBytes * 8.0 /
    //                            (stats[1].timeLastRxPacket.GetSeconds() -
    //                             stats[1].timeFirstRxPacket.GetSeconds()) /
    //                            1000000
    //                     << " Mbps" << std::endl;
    //           std::cout << "  Mean delay:   " << stats[1].delaySum.GetSeconds() / stats[1].rxPackets
    //                     << std::endl;
    //           std::cout << "  Mean jitter:   " << stats[1].jitterSum.GetSeconds() / (stats[1].rxPackets - 1)
    //                     << std::endl;
    //           auto dscpVec = classifier->GetDscpCounts(1);
    // }
    Ptr<Ipv4FlowClassifier> classifier;
    if (enableFlowMonitor)
    {
        monitor -> CheckForLostPackets();
        monitor -> SerializeToXmlFile(prefixfile + namefile + "ninth.flowmon", true, true);
        classifier = DynamicCast<Ipv4FlowClassifier>(flowmonHelper.GetClassifier());
        std::map<FlowId, FlowMonitor::FlowStats> stats = monitor->GetFlowStats();

        std::cout << std::endl << "*** Flow monitor statistics ***" << std::endl;

        // ---- Récapitulatif GLOBAL sur tous les flux (réponse pertes DropTail) ----
        uint64_t totalTx = 0, totalRx = 0, totalLost = 0, totalDropQueue = 0;
        uint32_t nbFlows = 0;
        for (auto it = stats.begin(); it != stats.end(); ++it)
        {
            totalTx   += it->second.txPackets;
            totalRx   += it->second.rxPackets;
            totalLost += it->second.lostPackets;
            if (it->second.packetsDropped.size() > Ipv4FlowProbe::DROP_QUEUE)
                totalDropQueue += it->second.packetsDropped[Ipv4FlowProbe::DROP_QUEUE];
            nbFlows++;
        }
        std::cout << "  [GLOBAL] flows=" << nbFlows
                  << "  Tx=" << totalTx
                  << "  Rx=" << totalRx
                  << "  Lost=" << totalLost
                  << "  DropByQueue=" << totalDropQueue
                  << std::endl;
        if (totalTx > 0)
            std::cout << "  [GLOBAL] loss ratio = "
                      << (100.0 * totalLost / totalTx) << " %" << std::endl;

        // ---- Détail du flux 1 (inchangé, pour compat) ----
        std::cout << "  Tx Packets/Bytes:   " << stats[1].txPackets << " / " << stats[1].txBytes
                  << std::endl;
        std::cout << "  Offered Load: "
                  << stats[1].txBytes * 8.0 /
                         (stats[1].timeLastTxPacket.GetSeconds() -
                          stats[1].timeFirstTxPacket.GetSeconds()) /
                         1000000
                  << " Mbps" << std::endl;
        std::cout << "  Rx Packets/Bytes:   " << stats[1].rxPackets << " / " << stats[1].rxBytes
                  << std::endl;
        uint32_t packetsDroppedByNetDevice = 0;
        uint64_t bytesDroppedByNetDevice = 0;
        if (stats[1].packetsDropped.size() > Ipv4FlowProbe::DROP_QUEUE)
        {
            packetsDroppedByNetDevice = stats[1].packetsDropped[Ipv4FlowProbe::DROP_QUEUE];
            bytesDroppedByNetDevice = stats[1].bytesDropped[Ipv4FlowProbe::DROP_QUEUE];
        }
        std::cout << "  Packets/Bytes Dropped by NetDevice:   " << packetsDroppedByNetDevice << " / "
                  << bytesDroppedByNetDevice << std::endl;
        std::cout << "  Throughput: "
                  << stats[1].rxBytes * 8.0 /
                         (stats[1].timeLastRxPacket.GetSeconds() -
                          stats[1].timeFirstRxPacket.GetSeconds()) /
                         1000000
                  << " Mbps" << std::endl;
        std::cout << "  Mean delay:   " << stats[1].delaySum.GetSeconds() / stats[1].rxPackets
                  << std::endl;
        std::cout << "  Mean jitter:   " << stats[1].jitterSum.GetSeconds() / (stats[1].rxPackets - 1)
                  << std::endl;
        auto dscpVec = classifier->GetDscpCounts(1);

        // sauvegarder dans un fichier
        std::ofstream dropCsv;
        std::string dropName = prefixfile + namefile + "_droptail_check.csv";
        bool newFile = !std::ifstream(dropName).good();
        dropCsv.open(dropName, std::ios::app);
        if (newFile)
            dropCsv << "parasite_rate,nb_hops,nb_detour,flows,tx,rx,lost,drop_queue\n";
        dropCsv << dataRateExt << "," << numExtraRouters << "," << numExtraDetour << ","
                << nbFlows << "," << totalTx << "," << totalRx << ","
                << totalLost << "," << totalDropQueue << "\n";
        dropCsv.close();
    }

   



    Simulator::Destroy();
    // traceFile.close();
    // queueFile.close();
    auto stop = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::minutes>(stop - start);
    std::cout << duration.count() << " minutes" << std::endl;
    return 0;
}