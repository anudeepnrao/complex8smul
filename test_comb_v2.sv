//SV EL
class Packet;
  bit              reset;
  rand bit              input_rdy;
  rand bit[3:-12] a_r;
  rand bit[3:-12] b_r;
  rand bit[3:-12] a_i;
  rand bit[3:-12] b_i;
  bit [7:-24]       p_r;
  bit [7:-24] 	    p_i;


  // Print contents of the data packet
  function void print(string tag="");
    $display ("T=%0t %s a_r=0x%0h a_i=0x%0h b_r=0x%0h b_i=0x%0h p_r=0x%0h p_i=0x%0h", $time, tag, a_r,a_i,b_r,b_i,p_r,p_i);
    $display("input_rdy = %0h  reset= %0h",input_rdy, reset);
  endfunction

  // This is a utility function to allow copying contents in
  // one Packet variable to another.
  function void copy(Packet tmp);
    this.a_r = tmp.a_r;
	this.a_i = tmp.a_i;
    this.b_r = tmp.b_r;
	this.b_i = tmp.b_i;
    this.reset = tmp.reset;
	this.input_rdy = tmp.input_rdy;
    this.p_r = tmp.p_r;
    this.p_i = tmp.p_i;
  endfunction
endclass

class driver;
  virtual cmul_if m_cmul_vif;
 // virtual clk_if  m_clk_vif;
  event drv_done;
  mailbox drv_mbx;

  task run();
    $display ("T=%0t [Driver] starting ...", $time);

    // Try to get a new transaction every time and then assign
    // packet contents to the interface. But do this only if the
    // design is ready to accept new transactions
    forever begin
      Packet item;

      $display ("T=%0t [Driver] waiting for item ...", $time);
      drv_mbx.get(item);
      @ (posedge m_cmul_vif.clk);
          item.print("Driver");
      m_cmul_vif.reset <= item.reset;
      m_cmul_vif.a_r <= item.a_r;
	  m_cmul_vif.a_i <= item.a_i;
      m_cmul_vif.b_r <= item.b_r;
	  m_cmul_vif.b_i <= item.b_i;
	  m_cmul_vif.input_rdy <= item.input_rdy;
      ->drv_done;
    end
  endtask
endclass

class monitor;
  virtual cmul_if      m_cmul_vif;
  //virtual clk_if        m_clk_vif;

  mailbox scb_mbx;              // Mailbox connected to scoreboard

  task run();
    $display ("T=%0t [Monitor] starting ...", $time);

    // Check forever at every clock edge to see if there is a
    // valid transaction and if yes, capture info into a class
    // object and send it to the scoreboard when the transaction
    // is over.
    forever begin
          Packet m_pkt = new();
      @(posedge m_cmul_vif.clk);
      #1;
        m_pkt.a_r         = m_cmul_vif.a_r;
		m_pkt.a_i         = m_cmul_vif.a_i;
        m_pkt.b_r         = m_cmul_vif.b_r;
		m_pkt.b_i         = m_cmul_vif.b_i;
        m_pkt.reset      = m_cmul_vif.reset;
        m_pkt.p_r       = m_cmul_vif.p_r;
        m_pkt.p_i = m_cmul_vif.p_i;
        m_pkt.print("Monitor");
      scb_mbx.put(m_pkt);
    end
  endtask
endclass

class scoreboard;
  mailbox scb_mbx;

  task run();
    forever begin
      Packet item, ref_item;
      scb_mbx.get(item);
      item.print("Scoreboard");

      // Copy contents from received packet into a new packet so
      // just to get a and b.
      ref_item = new();
      ref_item.copy(item);

      // Let us calculate the expected values in p_i and p_r
	  if (ref_item.input_rdy) begin
      if (ref_item.reset)
       {ref_item.p_i, ref_item.p_r} = 0; 
      else begin
      ref_item.p_r = {ref_item.a_r*ref_item.b_r} - {ref_item.a_i*ref_item.b_i};
	  ref_item.p_i = {ref_item.a_i*ref_item.b_r} + {ref_item.a_r*ref_item.b_i};
	  end
	  end

      // Now, p_i and p_r outputs in the reference variable can be compared
      // with those in the received packet
      if (ref_item.p_i != item.p_i) begin
        $display("[%0t] Scoreboard Error! p_i mismatch ref_item=0x%0h item=0x%0h", $time, ref_item.p_i, item.p_i);
      end else begin
        $display("[%0t] Scoreboard Pass! p_i match ref_item=0x%0h item =0x%0h", $time, ref_item.p_i, item.p_i);
      end

      if (ref_item.p_r != item.p_r) begin
        $display("[%0t] Scoreboard Error! p_r mismatch ref_item=0x%0h item=0x%0h", $time, ref_item.p_r, item.p_r);
      end else begin
        $display("[%0t] Scoreboard Pass! p_r match ref_item=0x%0h item=0x%0h", $time, ref_item.p_r, item.p_r);
      end
    end
  endtask
endclass

class generator;
  int   loop = 10;
  event drv_done;
  mailbox drv_mbx;

  task run();
    for (int i = 0; i < loop; i++) begin
      Packet item = new;
      item.randomize();
      $display ("T=%0t [Generator] Loop:%0d/%0d create next item", $time, i+1, loop);
      drv_mbx.put(item);
      $display ("T=%0t [Generator] Wait for driver to be done", $time);
      @(drv_done);
    end
  endtask
endclass

class env;  
  generator             g0; // Generate transactions         
  driver                        d0;                   // Driver to design  
  monitor                       m0;                    // Monitor from design
  scoreboard            s0;                     // Scoreboard connected to monitor
  mailbox                       scb_mbx;                // Top level mailbox for SCB <-> MON
  virtual cmul_if      m_cmul_vif;    // Virtual interface handle
//  virtual clk_if        m_clk_vif;              // TB clk

  event drv_done;
  mailbox drv_mbx;

  function new();
    d0 = new;
    m0 = new;
    s0 = new;
    scb_mbx = new();
    g0 = new;
    drv_mbx = new;
  endfunction

  virtual task run();
    // Connect virtual interface handles
    d0.m_cmul_vif = m_cmul_vif;
    m0.m_cmul_vif = m_cmul_vif;
  //  d0.m_clk_vif = m_clk_vif;
   //m0.m_clk_vif = m_clk_vif;

    // Connect mailboxes between each component
    d0.drv_mbx = drv_mbx;
    g0.drv_mbx = drv_mbx;

    m0.scb_mbx = scb_mbx;
    s0.scb_mbx = scb_mbx;

    // Connect event handles
    d0.drv_done = drv_done;
    g0.drv_done = drv_done;

    // Start all components - a fork join_any is used because
    // the stimulus is generated by the generator and we want the
    // simulation to exit only when the generator has finished
    // creating all transactions. Until then all other components
    // have to run in the background.
    fork
        s0.run();
                d0.run();
        m0.run();
        g0.run();
    join_any
  endtask
endclass

interface cmul_if();
  logic                 reset;
  logic					clk;
  logic					input_rdy;
  logic 				data_rdy;
  logic [3:-12] 		a_r;
  logic [3:-12] 		a_i;
  logic [3:-12] 		b_r;
  logic [3:-12] 		b_i;
  logic [7:-24]         p_r;
  logic [7:-24] 	    p_i;
  initial clk <= 0;
  initial begin
    reset <=1;
    #20 reset =0;
  end

  always #10 clk = ~clk;
endinterface

class test;
  env e0;
  mailbox drv_mbx;

  function new();
    drv_mbx = new();
    e0 = new();
  endfunction

  virtual task run();
    e0.d0.drv_mbx = drv_mbx;
    e0.run();
  endtask
endclass

module tb;

  bit tb_clk;

  //clk_if        m_clk_if();
  cmul_if      m_cmul_if();
  multiplier      m0          (m_cmul_if);

  initial begin
    test t0;
    t0 = new;
    t0.e0.m_cmul_vif = m_cmul_if;
    //t0.e0.m_clk_vif = m_clk_if;
    $dumpfile("dump.vcd");
  $dumpvars;
    t0.run();

    // Once the main stimulus is over, wait for some time
    // until all transactions are finished and then end
    // simulation. Note that $finish is required because
    // there are components that are running forever in
    // the background like clk, monitor, driver, etc
    #50 $finish;
  end
  endmodule
  
  