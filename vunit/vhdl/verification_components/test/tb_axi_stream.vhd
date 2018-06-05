-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.
--
-- Copyright (c) 2014-2018, Lars Asplund lars.anders.asplund@gmail.com

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

context work.vunit_context;
context work.com_context;
context work.data_types_context;
use work.axi_stream_pkg.all;
use work.stream_master_pkg.all;
use work.stream_slave_pkg.all;

entity tb_axi_stream is
  generic (runner_cfg : string);
end entity;

architecture a of tb_axi_stream is
  constant master_axi_stream : axi_stream_master_t := new_axi_stream_master(data_length => 8);
  constant master_stream : stream_master_t := as_stream(master_axi_stream);

  constant slave_axi_stream : axi_stream_slave_t := new_axi_stream_slave(data_length => 8);
  constant slave_stream : stream_slave_t := as_stream(slave_axi_stream);

  constant monitor : axi_stream_monitor_t :=
    new_axi_stream_monitor(data_length => 8,
    logger => get_logger("monitor", parent => axi_stream_logger),
    actor => new_actor("monitor")
    );

  signal aclk   : std_logic := '0';
  signal tvalid : std_logic;
  signal tready : std_logic;
  signal tdata  : std_logic_vector(data_length(slave_axi_stream)-1 downto 0);
  signal tlast : std_logic;
begin

  main : process
    constant subscriber : actor_t := new_actor;
    variable data : std_logic_vector(tdata'range);
    variable last : boolean;
    variable reference_queue : queue_t := new_queue;
    variable reference : stream_reference_t;
    variable msg : msg_t;
    variable msg_type : msg_type_t;
    variable axi_stream_transaction : axi_stream_transaction_t(tdata(tdata'range));

    procedure get_axi_stream_transaction(variable axi_stream_transaction : out axi_stream_transaction_t) is
    begin
      receive(net, subscriber, msg);
      msg_type := message_type(msg);
      handle_axi_stream_transaction(msg_type, msg, axi_stream_transaction);
      check(is_already_handled(msg_type));
    end;
  begin
    test_runner_setup(runner, runner_cfg);
    subscribe(subscriber, find("monitor"));
    show(axi_stream_logger, display_handler, debug);

    if run("test single push and pop") then
      push_stream(net, master_stream, x"77");
      pop_stream(net, slave_stream, data);
      check_equal(data, std_logic_vector'(x"77"), result("for pop stream data"));

      get_axi_stream_transaction(axi_stream_transaction);
      check_equal(
        axi_stream_transaction.tdata,
        std_logic_vector'(x"77"),
        result("for axi_stream_transaction.tdata")
      );

    elsif run("test single push and pop with tlast") then
      push_stream(net, master_stream, x"88", true);
      pop_stream(net, slave_stream, data, last);
      check_equal(data, std_logic_vector'(x"88"), result("for pop stream data"));
      check(last, result("for pop stream last"));

      get_axi_stream_transaction(axi_stream_transaction);
      check_equal(
        axi_stream_transaction.tdata,
        std_logic_vector'(x"88"),
        result("for axi_stream_transaction.tdata")
      );
      check(axi_stream_transaction.tlast, result("for axi_stream_transaction.tlast"));

    elsif run("test single axi push and pop") then
      push_axi_stream(net, master_axi_stream, x"99", tlast => '0');
      pop_stream(net, slave_stream, data, last);
      check_equal(data, std_logic_vector'(x"99"), result("for pop stream data"));
      check_false(last, result("for pop stream last"));

      get_axi_stream_transaction(axi_stream_transaction);
      check_equal(
        axi_stream_transaction.tdata,
        std_logic_vector'(x"99"),
        result("for axi_stream_transaction.tdata")
      );
      check_false(axi_stream_transaction.tlast, result("for axi_stream_transaction.tlast"));

    elsif run("test pop before push") then
      for i in 0 to 7 loop
        pop_stream(net, slave_stream, reference);
        push(reference_queue, reference);
      end loop;

      for i in 0 to 7 loop
        push_stream(net, master_stream,
                    std_logic_vector(to_unsigned(i+1, data'length)));
      end loop;

      for i in 0 to 7 loop
        reference := pop(reference_queue);
        await_pop_stream_reply(net, reference, data);
        check_equal(data, to_unsigned(i+1, data'length), result("for await pop stream data"));

        get_axi_stream_transaction(axi_stream_transaction);
        check_equal(
          axi_stream_transaction.tdata,
          to_unsigned(i+1, data'length),
          result("for axi_stream_transaction.tdata")
        );
      end loop;
    end if;
    test_runner_cleanup(runner);
  end process;
  test_runner_watchdog(runner, 10 ms);

  axi_stream_master_inst : entity work.axi_stream_master
    generic map (
      master => master_axi_stream)
    port map (
      aclk   => aclk,
      tvalid => tvalid,
      tready => tready,
      tdata  => tdata,
      tlast  => tlast);

  axi_stream_slave_inst : entity work.axi_stream_slave
    generic map (
      slave => slave_axi_stream)
    port map (
      aclk   => aclk,
      tvalid => tvalid,
      tready => tready,
      tdata  => tdata,
      tlast  => tlast);

  axi_stream_monitor_inst : entity work.axi_stream_monitor
    generic map(
      monitor => monitor
    )
    port map(
      aclk   => aclk,
      tvalid => tvalid,
      tready => tready,
      tdata  => tdata,
      tlast  => tlast
    );


  aclk <= not aclk after 5 ns;
end architecture;
