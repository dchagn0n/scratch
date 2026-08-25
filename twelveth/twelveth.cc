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

// class backbone variable udp app
#include "ns3/application.h"
#include "ns3/address.h"
#include "ns3/traced-value.h"
#include "ns3/double.h"
#include "ns3/uinteger.h"
#include "ns3/boolean.h"
#include "ns3/log.h"
#include "ns3/socket.h"
#include "ns3/udp-socket-factory.h"
#include "ns3/simulator.h"
#include "ns3/nstime.h"
#include "ns3/ptr.h"
#include "ns3/trace-source-accessor.h"
#include <algorithm>

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

//#include "backbone-variable-udp-app.h"

using namespace ns3;

NS_LOG_COMPONENT_DEFINE("FluctuatingTrafficExample");

namespace ns3 {
class BackboneVariableUdpApp : public Application
{
public:
  static TypeId GetTypeId()
  {
    static TypeId tid = TypeId("ns3::BackboneVariableUdpApp")
      .SetParent<Application>()
      .SetGroupName("Applications")
      .AddConstructor<BackboneVariableUdpApp>()

      .AddAttribute("Remote", "Remote address (IPv4/IPv6 + port).",
                    AddressValue(),
                    MakeAddressAccessor(&BackboneVariableUdpApp::m_peer),
                    MakeAddressChecker())

      .AddAttribute("Step", "Update period (e.g., 10ms).",
                    TimeValue(MilliSeconds(10)),
                    MakeTimeAccessor(&BackboneVariableUdpApp::m_step),
                    MakeTimeChecker())

      .AddAttribute("PacketSize", "UDP payload size in bytes.",
                    UintegerValue(1200),
                    MakeUintegerAccessor(&BackboneVariableUdpApp::m_pktSize),
                    MakeUintegerChecker<uint32_t>(1))

      .AddAttribute("RminMbps", "Minimum rate (Mb/s).",
                    DoubleValue(1.0),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_rMin),
                    MakeDoubleChecker<double>(0.0))

      .AddAttribute("RmaxMbps", "Maximum rate (Mb/s).",
                    DoubleValue(160.0),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_rMax),
                    MakeDoubleChecker<double>(0.0))

      // B2 AR(1)
      .AddAttribute("Phi", "AR(1) coefficient.",
                    DoubleValue(0.985),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_phi),
                    MakeDoubleChecker<double>(0.0, 0.999999))

      // Low-pass
      .AddAttribute("TauSeconds", "Low-pass time constant tau (s). Order=3 cascade.",
                    DoubleValue(3.0),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_tau),
                    MakeDoubleChecker<double>(1e-6))

      // EWMA memory target W and reactive lambda = 2*dt/(W+dt)
      .AddAttribute("EwmaWindowSeconds", "Target EWMA memory W (s).",
                    DoubleValue(10.0),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_W),
                    MakeDoubleChecker<double>(1e-6))

      // Stabilized rescale parameters
      .AddAttribute("SigmaMinMbps", "Floor for EWMA std-dev (Mb/s).",
                    DoubleValue(5.0),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_sigmaMin),
                    MakeDoubleChecker<double>(0.0))

      .AddAttribute("Umax", "Clamp for z-score.",
                    DoubleValue(2.5),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_uMax),
                    MakeDoubleChecker<double>(0.1))

      .AddAttribute("Beta", "tanh slope parameter.",
                    DoubleValue(0.5),
                    MakeDoubleAccessor(&BackboneVariableUdpApp::m_beta),
                    MakeDoubleChecker<double>(1e-6))

      .AddAttribute("SeedStream", "Stream number for RNG (determinism).",
                    UintegerValue(1),
                    MakeUintegerAccessor(&BackboneVariableUdpApp::m_stream),
                    MakeUintegerChecker<uint32_t>())

      .AddTraceSource("TargetRateMbps",
                      "Current target rate R_k in Mb/s.",
                      MakeTraceSourceAccessor(&BackboneVariableUdpApp::m_rateTrace),
                      "ns3::TracedValueCallback::Double");
    return tid;
  }

  BackboneVariableUdpApp() = default;
  ~BackboneVariableUdpApp() override = default;

private:
  void StartApplication() override
  {
    NS_LOG_INFO("Starting BackboneVariableUdpApp");
    if (!m_socket)
    {
      m_socket = Socket::CreateSocket(GetNode(), UdpSocketFactory::GetTypeId());
      m_socket->Connect(m_peer);
    }

    // RNG: Normal(0, sigma)
    m_norm = CreateObject<NormalRandomVariable>();
    m_norm->SetStream(m_stream);

    // Initialize time step values
    m_dt = m_step.GetSeconds();
    // AR(1) noise sigma to keep Var(y)≈1
    m_arSigma = std::sqrt(std::max(1.0 - m_phi * m_phi, 0.0));

    // LPF alpha
    m_alpha = m_dt / m_tau;

    // EWMA "very reactive"
    m_lambda = (2.0 * m_dt) / (m_W + m_dt);

    // Initialize state (simple, stable)
    m_y = 0.0;
    double z0 = MapPhi(m_y);   // in [rMin, rMax]
    m_x1 = z0; m_x2 = z0; m_x3 = z0;
    m_mu = m_x3;
    m_m2 = m_x3 * m_x3;
    m_tokens = 0.0;

    m_running = true;
    ScheduleNextTick();
  }

  void StopApplication() override
  {
    NS_LOG_INFO("Stopping BackboneVariableUdpApp");
    m_running = false;
    if (m_event.IsPending()) Simulator::Cancel(m_event);
    if (m_socket) m_socket->Close();
    m_socket = nullptr;
  }

  void ScheduleNextTick()
  {
    m_event = Simulator::Schedule(m_step, &BackboneVariableUdpApp::Tick, this);
  }

  // Normal CDF Phi using erf (no special libs needed)
  static double NormalCdf(double x)
  {
    return 0.5 * (1.0 + std::erf(x / std::sqrt(2.0)));
  }

  double MapPhi(double y) const
  {
    double u = NormalCdf(y);
    return m_rMin + (m_rMax - m_rMin) * u;
  }

  void Tick()
  {
    if (!m_running) return;

    // ----- (A) AR(1) latent -----
    // epsilon ~ N(0, arSigma^2)
    double eps = m_norm->GetValue(0.0, m_arSigma*m_arSigma);
    m_y = m_phi * m_y + eps;

    // ----- (B) bounded raw rate z_k -----
    double z = MapPhi(m_y);

    // ----- (C) LPF order 3 -----
    m_x1 = (1.0 - m_alpha) * m_x1 + m_alpha * z;
    m_x2 = (1.0 - m_alpha) * m_x2 + m_alpha * m_x1;
    m_x3 = (1.0 - m_alpha) * m_x3 + m_alpha * m_x2;

    // ----- (D) EWMA mean + second moment -----
    m_mu = (1.0 - m_lambda) * m_mu + m_lambda * m_x3;
    m_m2 = (1.0 - m_lambda) * m_m2 + m_lambda * (m_x3 * m_x3);

    double var = std::max(m_m2 - m_mu * m_mu, 0.0);
    double sd  = std::sqrt(var);
    sd = std::max(sd, m_sigmaMin);

    // ----- (E) z-score + clamp -----
    double u = (m_x3 - m_mu) / (sd + 1e-6);
    u = std::min(std::max(u, -m_uMax), m_uMax);

    // ----- (F) tanh mapping to [rMin, rMax] -----
    double s = 0.5 * (1.0 + std::tanh(m_beta * u));
    double R = m_rMin + (m_rMax - m_rMin) * s; // Mb/s

    // Trace target rate
    m_rateTrace = R;

    // ----- Send according to token bucket budget over this step -----
    double bytesBudget = (R * 1e6 / 8.0) * m_dt; // Mb/s -> bytes in dt
    m_tokens += bytesBudget;

    while (m_tokens >= m_pktSize)
    {
      Ptr<Packet> p = Create<Packet>(m_pktSize);
      m_socket->Send(p);
      m_tokens -= m_pktSize;
    }

    ScheduleNextTick();
  }

private:
  // Attributes
  Address   m_peer;
  Time      m_step;
  uint32_t  m_pktSize = 1200;

  double m_rMin = 1.0;
  double m_rMax = 160.0;

  double m_phi = 0.985;
  double m_tau = 3.0;
  double m_W   = 10.0;

  double m_sigmaMin = 5.0;
  double m_uMax = 2.5;
  double m_beta = 0.5;

  uint32_t m_stream = 1;

  // Runtime
  Ptr<Socket> m_socket;
  EventId     m_event;
  bool        m_running = false;

  Ptr<NormalRandomVariable> m_norm;

  double m_dt = 0.01;

  // Derived params
  double m_arSigma = 0.173;
  double m_alpha = 0.00333;
  double m_lambda = 0.0020;

  // Generator state
  double m_y = 0.0;
  double m_x1 = 0.0, m_x2 = 0.0, m_x3 = 0.0;

  // EWMA state
  double m_mu = 0.0;
  double m_m2 = 0.0;

  // Token bucket
  double m_tokens = 0.0;

  // Trace
  TracedValue<double> m_rateTrace;
};
} // namespace ns3

/**
 * Number of packets in queue trace.
 *
 * @param stream Output stream.
 * @param oldValue Old value.
 * @param newValue New value.
 */
void
PacketsInQueueTrace(Ptr<OutputStreamWrapper> stream, uint32_t oldValue, uint32_t newValue)
{
    *stream->GetStream() << Simulator::Now().GetSeconds() << ";" << oldValue << ";" << newValue << std::endl;
}

void
RateLogger(Ptr<OutputStreamWrapper> stream, double oldv, double newv)
{
  *stream->GetStream() <<  Simulator::Now().GetSeconds()<< ";" << oldv << ";" << newv << std::endl;
}

const double PI = std::acos(-1);

struct Point {
    double x, y;
};

/**
 * Generate n points along the semicircle defined by the diameter (X1,Y1)-(X2,Y2).
 *
 * @param X1 X coordinate of the first extremity of the diameter.
 * @param Y1 Y coordinate of the first extremity of the diameter.
 * @param X2 X coordinate of the second extremity of the diameter.
 * @param Y2 Y coordinate of the second extremity of the diameter.
 * @param n Number of points to generate (must be >= 2).
 * @return Vector of points along the semicircle.
 */
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

/**
 * Parse a rate string (e.g., "100Mbps") and convert it to bps.
 *
 * @param rate Rate string to parse.
 * @return Rate in bits per second (bps).
 */
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
   
    bool enableFlowMonitor = false;
    uint32_t scaleFactor = 1;  // Facteur d'échelle pour ajuster la taille du réseau
    std::string bandwidth = "100bps";
    std::string bandwidth_ext = bandwidth;
    std::string dataRateAccess = "10bps";
    std::string dataRateExt = "10bps";
    //std::string dataRate_app = "50Mbps";
    //std::string dataRateExt_app = "50Mbps";
    uint32_t packetSize = 12000;  // Taille des paquets (en bits)
    std::string latency_direct = "5ms";
    std::string latency_detour = "2ms";
    //uint32_t netdevicesQueueSize = 50;

    std::string transportProt = "Udp";
    std::string socketType;
    std::string socketType_Ext = "ns3::UdpSocketFactory";

    float startTime = 0.01F; // in s
    float simulationTime = 10; // in s
    
    uint32_t numExtraRouters = 0;
    uint32_t numExtraDetour = 3;

    double exp_mean = 0.5;
    double exp_mean_para = 0.5;

    std::string repertory = "scratch/twelveth/";

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

    /* Set random seed and run based on repertory name */
    // Compute a 32-bit hash from the string
    uint32_t seed = static_cast<uint32_t>(std::hash<std::string>{}(repertory));
    // You may also want to use a different value for SetRun if you run multiple simulations
    uint32_t run = seed % 10000; // example: derived smaller run index
    RngSeedManager::SetSeed(seed);
    RngSeedManager::SetRun(run);

    std::cout << "Using seed = " << seed << " and run = " << run << std::endl;

    /* Determine socket type */
    if (transportProt == "Tcp")
    {
        socketType = "ns3::TcpSocketFactory";
    }
    else
    {
        socketType = "ns3::UdpSocketFactory";
    }

    /*  */
    std::string prefixfile = repertory + "/";
    std::string namefile = "T"+std::to_string(simulationTime) + "s_h" + std::to_string(numExtraRouters) + "_a" + std::to_string(numExtraDetour) + "_"
    + "L"+latency_direct+ "_B"+bandwidth + "_Ra"+dataRateAccess +"_Re"+dataRateExt + "_P"+std::to_string(packetSize) + "b_" + transportProt + "_Ma" + std::to_string(exp_mean) + "_Me" + std::to_string(exp_mean_para) + "_";
    std::cout << prefixfile << namefile << std::endl;

    // latency of detour path is half of the direct path
    int pos = latency_direct.find("ms");
    uint32_t latency_direct_float = std::stof(latency_direct.substr(0,pos));
    latency_detour = std::to_string(latency_direct_float/2) + "ms";
    latency_detour = latency_direct; // latency_detour = latency_direct for testing
    std::cout << "latency detour: " << latency_detour << std::endl;

    std::cout << "bandwidth: " << bandwidth << std::endl;

    float bandwidth_float = parseRateToBps(bandwidth); 
    
    std::cout << "dataRateAccess: " << dataRateAccess << std::endl;

    // bandwidth of external links: *2 if higher than backbone bandwidth
    float dataRateExt_float = parseRateToBps(dataRateExt); 
    if (dataRateExt_float >= bandwidth_float)// 
    {
        bandwidth_ext = std::to_string(2*dataRateExt_float) + "bps"; //+ dataRateExt.substr(pos-1, 1) +
        //dataRateExt = bandwidth;
    }else{
        bandwidth_ext = bandwidth;
    }
    std::cout << "bandwidth_ext: " << bandwidth_ext << std::endl;
    std::cout << "dataRateExt: " << dataRateExt << std::endl;

    float dataRateExt_D0_float = dataRateExt_float ;//* (2 + numExtraDetour);  // equilibre les fluxs détournés et directes vers D1
    std::string dataRateExt_D0 = std::to_string(dataRateExt_D0_float) + "bps"; 
    std::cout << "dataRateExt_D0: " << dataRateExt_D0 << std::endl;

    float stopTime = startTime + simulationTime;

    //Time::SetResolution(Time::NS);

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

    /* Create extra routers and parasite nodes if needed */
    if (numExtraRouters > 0)
    {
        extraRouters.Create(numExtraRouters); // Nœuds supplémentaires pour allonger le chemin
        parasiteNodes.Create(numExtraRouters); // Un parasite par routeur
    }

    /* Create extra detour routers and parasite nodes if needed */
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
         //NetDeviceContainer distDevices0_direct = distLink.Install(accessRouters.Get(0), distRouters.Get(0));
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
    NetDeviceContainer extDev1_direct = extHelper.Install(external1Nodes.Get(0), distRouters.Get(1));
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
    staticAccess0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), firstHop, 1);
    //staticAccess0->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),lan0_direct.GetAddress(1), 1);
    //staticAccess0->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),lan0_direct.GetAddress(1), 1);
    //staticAccess0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0) , Ipv4Mask("255.255.255.0"),lan0_direct.GetAddress(1), 1);
    //staticAccess0->AddNetworkRouteTo(ext1Interfaces_detour.GetAddress(0) , Ipv4Mask("255.255.255.0"),lan0_direct.GetAddress(1), 1);
    
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
        }

        Ptr<Node> currentRouter = extraRouters.Get(numExtraRouters - 1);
        Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> routingLast = staticRouting.GetStaticRouting(ipv4_extra);
        Ipv4Address nextHopToD0 = chainIfaces[numExtraRouters].GetAddress(1); // vers D0
        uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(chainDevices[numExtraRouters].Get(0));
        routingLast->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD0, ifaceIndex);
        routingLast->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHopToD0, ifaceIndex);
    }

    // Example route: From dist0 to dist1 via dist2
    uint32_t ifaceIndex = ipv4_dist0->GetInterfaceForDevice(backbone02.Get(0));
    staticDist0->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"),iface02.GetAddress(1), ifaceIndex); 
    
    ifaceIndex = ipv4_dist0->GetInterfaceForDevice(backbone01.Get(0));
    staticDist0->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"),iface01.GetAddress(1), ifaceIndex); 
    staticDist0->AddNetworkRouteTo(ext1Interfaces_direct.GetAddress(0) , Ipv4Mask("255.255.255.0"),iface01.GetAddress(1), ifaceIndex);
    
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

            routing->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), nextHop, ifaceIndex);
        }

        Ptr<Node> currentRouter = extraDetour.Get(numExtraDetour - 1);
        Ptr<Ipv4> ipv4_extra = currentRouter->GetObject<Ipv4>();
        Ptr<Ipv4StaticRouting> routingLast = staticRouting.GetStaticRouting(ipv4_extra);
        Ipv4Address nextHopToD1 = detourChainIfaces[numExtraDetour].GetAddress(1); // vers D1
        uint32_t ifaceIndex = ipv4_extra->GetInterfaceForDevice(detourChainDevices[numExtraDetour].Get(0));
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

    // E0 : route par défaut vers D0 uniquement (1 saut).
    ifaceIndex = ipv4_ext0->GetInterfaceForDevice(extDev0.Get(0));
    staticExt0->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), ext0Interfaces.GetAddress(1), ifaceIndex);

    // E1 : routes de retour vers E0 + routes vers A1 pour les parasites locaux.
    ifaceIndex = ipv4_ext1->GetInterfaceForDevice(extDev1_direct.Get(0));
    staticExt1->AddNetworkRouteTo(ext0Interfaces.GetAddress(0), Ipv4Mask("255.255.255.0"), ext1Interfaces_direct.GetAddress(1), ifaceIndex);
    staticExt1->AddNetworkRouteTo(lan1_direct.GetAddress(0), Ipv4Mask("255.255.255.0"), ext1Interfaces_direct.GetAddress(1), ifaceIndex);
    staticExt1->AddNetworkRouteTo(lan1_detour.GetAddress(0), Ipv4Mask("255.255.255.0"), ext1Interfaces_direct.GetAddress(1), ifaceIndex);
    // E2 : route par défaut vers D2 uniquement (1 saut).
    ifaceIndex = ipv4_ext2->GetInterfaceForDevice(extDev2.Get(0));
    staticExt2->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), ext2Interfaces.GetAddress(1), ifaceIndex);

    if (numExtraRouters > 0 )
    {
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            Ptr<Node> parasite = parasiteNodes.Get(i);
            Ipv4Address nextHop = parasiteIfaces[i].GetAddress(1);
            Ptr<Ipv4> ipv4_para = parasite->GetObject<Ipv4>();
            ifaceIndex = ipv4_para->GetInterfaceForDevice(parasiteDevices[i].Get(0));
            Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_para);
            routing->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHop, ifaceIndex);
        }
    }

    for (uint32_t i = 0; i < numExtraDetour; ++i)
    {
        Ptr<Node> parasite = parasiteDetour.Get(i);
        Ipv4Address nextHop = detourParasiteIfaces[i].GetAddress(1);
        Ptr<Ipv4> ipv4_para = parasite->GetObject<Ipv4>();
        ifaceIndex = ipv4_para->GetInterfaceForDevice(detourParasiteDevices[i].Get(0));
        Ptr<Ipv4StaticRouting> routing = staticRouting.GetStaticRouting(ipv4_para);
        routing->AddNetworkRouteTo(Ipv4Address("0.0.0.0"), Ipv4Mask("0.0.0.0"), nextHop, ifaceIndex);
    }

    std::string animFile = prefixfile + namefile +"animation.xml"; // Name of file for animation output 
    //std::string animRouting = prefixfile + namefile +"animation_routing.xml"; // Name of file for animation output 
    // Create the animation object and configure for specified output
    AnimationInterface anim(animFile);
    anim.EnablePacketMetadata(true); // Optional
    
    // 
    // 
    // 
    // 
    // 
    // 
    // 
    //anim.EnableIpv4RouteTracking(animRouting, Seconds(startTime), Seconds(stopTime));

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

    // Global stream counter for BackboneVariableUdpApp RNG independence
    uint32_t streamCounter = 100;

    // Parasite E0 → D1 (1 saut : D0→D1 via backbone01). Stress la file partagée avec le flux direct.
    std::cout << "numFlow parasite E0 direct (1 saut D0->D1): " << numFlowsExt << std::endl;
    {
        const uint16_t portE0direct = static_cast<uint16_t>(6001 + port + numFlows_direct + numFlows_detour);
        Address dstAddr(InetSocketAddress(iface01.GetAddress(1), portE0direct));

        UdpServerHelper serverE0d(portE0direct);
        ApplicationContainer sinkE0d = serverE0d.Install(distRouters.Get(1)); // D1 — terminus
        sinkE0d.Start(Seconds(startTime));
        sinkE0d.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            external0Nodes.Get(0)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));
            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteDirectExtraRouter_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasite E0 → D2 (1 saut : D0→D2 via backbone02). Stress la file partagée avec le flux détourné.
    std::cout << "numFlow parasite E0 detour (1 saut D0->D2): " << numFlowsExt << std::endl;
    {
        const uint16_t portE0detour = static_cast<uint16_t>(6002 + port + numFlows_direct + numFlows_detour);
        Address dstAddr(InetSocketAddress(iface02.GetAddress(1), portE0detour));

        UdpServerHelper serverE0dt(portE0detour);
        ApplicationContainer sinkE0dt = serverE0dt.Install(distRouters.Get(2)); // D2 — terminus
        sinkE0dt.Start(Seconds(startTime));
        sinkE0dt.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            external0Nodes.Get(0)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));
            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteDetourExtraRouter_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasite E2 → premier saut détour depuis D2 (1 saut). Stress D2→extraDetour[0] ou D2→D1.
    std::cout << "numFlow parasite E2 (1 saut D2->suivant): " << numFlowsExt << std::endl;
    {
        const uint16_t portE2 = static_cast<uint16_t>(6003 + port + numFlows_direct + numFlows_detour);
        Ipv4Address dstIP = detourChainIfaces[0].GetAddress(1);
        Ptr<Node> sinkNodeE2 = (numExtraDetour > 0) ? extraDetour.Get(0) : distRouters.Get(1);
        Address dstAddr(InetSocketAddress(dstIP, portE2));

        UdpServerHelper serverE2(portE2);
        ApplicationContainer sinkE2 = serverE2.Install(sinkNodeE2);
        sinkE2.Start(Seconds(startTime));
        sinkE2.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            external2Nodes.Get(0)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));
            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteFromD2ExtraRouter_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasites de la chaîne directe : chaque parasiteNodes[i] envoie vers le routeur suivant (1 saut).
    if (numExtraRouters > 0)
    {
        const uint16_t parasiteChainPortBase = static_cast<uint16_t>(7000 + port + numFlows_direct + numFlows_detour);
        for (uint32_t i = 0; i < numExtraRouters; ++i)
        {
            Ipv4Address nextRouterIP = chainIfaces[i + 1].GetAddress(1);
            uint16_t localPort = parasiteChainPortBase + static_cast<uint16_t>(i);
            Address dstAddr(InetSocketAddress(nextRouterIP, localPort));

            Ptr<Node> sinkNode = (i < numExtraRouters - 1) ? extraRouters.Get(i + 1) : distRouters.Get(0);
            UdpServerHelper serverChain(localPort);
            ApplicationContainer sinkChain = serverChain.Install(sinkNode);
            sinkChain.Start(Seconds(startTime));
            sinkChain.Stop(Seconds(stopTime + 2));

            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            parasiteNodes.Get(i)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));

            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteExtraRouter_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasites de la chaîne détour : chaque parasiteDetour[i] envoie vers le routeur suivant (1 saut).
    if (numExtraDetour > 0)
    {
        const uint16_t parasiteDetourPortBase = static_cast<uint16_t>(
            7000 + port + numFlows_direct + numFlows_detour + numExtraRouters);
        for (uint32_t i = 0; i < numExtraDetour; ++i)
        {
            Ipv4Address nextRouterIP = detourChainIfaces[i + 1].GetAddress(1);
            uint16_t localPort = parasiteDetourPortBase + static_cast<uint16_t>(i);
            Address dstAddr(InetSocketAddress(nextRouterIP, localPort));

            Ptr<Node> sinkNode = (i < numExtraDetour - 1) ? extraDetour.Get(i + 1) : distRouters.Get(1);
            UdpServerHelper serverDetour(localPort);
            ApplicationContainer sinkDetour = serverDetour.Install(sinkNode);
            sinkDetour.Start(Seconds(startTime));
            sinkDetour.Stop(Seconds(stopTime + 2));

            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            parasiteDetour.Get(i)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));

            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteDetour2ExtraRouter_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasites E1 → A1 via lien direct (stress D1→A1 direct, partagé avec le flux direct).
    {
        const uint16_t portE1direct = static_cast<uint16_t>(6004 + port + numFlows_direct + numFlows_detour);
        Address dstAddr(InetSocketAddress(lan1_direct.GetAddress(0), portE1direct));

        UdpServerHelper serverE1d(portE1direct);
        ApplicationContainer sinkE1d = serverE1d.Install(accessRouters.Get(1)); // A1 — terminus
        sinkE1d.Start(Seconds(startTime));
        sinkE1d.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            external1Nodes.Get(0)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));
            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteE1Direct_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
        }
    }

    // Parasites E1 → A1 via lien détour (stress D1→A1 détour, partagé avec le flux détourné).
    {
        const uint16_t portE1detour = static_cast<uint16_t>(6005 + port + numFlows_direct + numFlows_detour);
        Address dstAddr(InetSocketAddress(lan1_detour.GetAddress(0), portE1detour));

        UdpServerHelper serverE1dt(portE1detour);
        ApplicationContainer sinkE1dt = serverE1dt.Install(accessRouters.Get(1)); // A1 — terminus
        sinkE1dt.Start(Seconds(startTime));
        sinkE1dt.Stop(Seconds(stopTime + 2));

        for (uint32_t i = 0; i < numFlowsExt; ++i) {
            Ptr<ns3::BackboneVariableUdpApp> app = CreateObject<ns3::BackboneVariableUdpApp>();
            app->SetAttribute("Remote", AddressValue(dstAddr));
            app->SetAttribute("PacketSize", UintegerValue(1200));
            app->SetAttribute("Step", TimeValue(MilliSeconds(10)));
            app->SetAttribute("Phi", DoubleValue(0.985));
            app->SetAttribute("TauSeconds", DoubleValue(3.0));
            app->SetAttribute("EwmaWindowSeconds", DoubleValue(10.0));
            app->SetAttribute("SigmaMinMbps", DoubleValue(5.0));
            app->SetAttribute("Umax", DoubleValue(2.5));
            app->SetAttribute("Beta", DoubleValue(0.5));
            app->SetAttribute("RminMbps", DoubleValue(1.0));
            app->SetAttribute("RmaxMbps", DoubleValue(160.0));
            app->SetAttribute("SeedStream", UintegerValue(streamCounter++));
            external1Nodes.Get(0)->AddApplication(app);
            app->SetStartTime(Seconds(startTime));
            app->SetStopTime(Seconds(stopTime));
            Ptr<OutputStreamWrapper> streamRateLogger = ascii.CreateFileStream(
                prefixfile + namefile + "parasiteE1Detour_" + std::to_string(i) + ".txt");
            app->TraceConnectWithoutContext("TargetRateMbps", MakeBoundCallback(&RateLogger, streamRateLogger));
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
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-direct_dist1",   distDevices1_direct.Get(1), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-detour_access1", distDevices1_detour.Get(0), true);
    distLink.EnablePcap(prefixfile + namefile + "trace-dist1-access1-detour_dist1",   distDevices1_detour.Get(1), true);
    
    // //AsciiTraceHelper ascii2;
    // backbone_direct.EnableAsciiAll(ascii.CreateFileStream(prefixfile + namefile + "ninth-backbone_direct.tr"));
    // backbone_detour.EnableAsciiAll(ascii.CreateFileStream(prefixfile + namefile + "ninth-backbone_detour.tr"));
    // distLink.EnableAsciiAll(ascii.CreateFileStream(prefixfile + namefile + "ninth-distLink.tr"));
    // extHelper.EnableAsciiAll(ascii.CreateFileStream(prefixfile + namefile + "ninth-extHelper.tr"));

    //distLink.EnableAscii(prefixfile + namefile + "ninth-distLink", distDevices0_direct);
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
        //distLink.EnableAscii(prefixfile + namefile + "ninth-backbone", detourChainDevices[numExtraDetour]);
        backbone_detour.EnableAscii(prefixfile + namefile + "ninth-backbone", detourChainDevices[numExtraDetour]);
    } else {
        backbone_detour.EnableAscii(prefixfile + namefile + "ninth-backbone", backbone21);
    }

    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev0);
    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev1_direct);
    extHelper.EnableAscii(prefixfile + namefile + "ninth-ext", extDev2);

    FlowMonitorHelper flowmonHelper;
    Ptr<FlowMonitor> monitor;
    if (enableFlowMonitor)
    {
        monitor = flowmonHelper.InstallAll();
    }

    std::cout << "stopTime:"<< stopTime << std::endl;
    Simulator::Stop(Seconds(stopTime + 5));
    Simulator::Run();
    std::cout << "Simulation ended at " << Simulator::Now().GetSeconds() << "s" << std::endl;

    Ptr<Ipv4FlowClassifier> classifier;
    if (enableFlowMonitor)
    {
        monitor -> CheckForLostPackets();
        monitor -> SerializeToXmlFile(prefixfile + namefile + "ninth.flowmon", true, true);
        classifier = DynamicCast<Ipv4FlowClassifier>(flowmonHelper.GetClassifier());
    std::map<FlowId, FlowMonitor::FlowStats> stats = monitor->GetFlowStats();
    std::cout << std::endl << "*** Flow monitor statistics ***" << std::endl;
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
    }

    Simulator::Destroy();
    // traceFile.close();
    // queueFile.close();
    auto stop = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::minutes>(stop - start);
    std::cout << duration.count() << " minutes" << std::endl;
    return 0;
}