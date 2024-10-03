defmodule HordePro.DynamicSupervisor do
  # child_spec/1
  # count_children/1
  # init/1
  # start_child/2
  # start_link/1
  # start_link/3
  # stop/3
  # terminate_child/2
  # which_children/1

  # Strategy:
  # lock_id = gen_id() |> acquire_lock()
  #
  # when we start a process, we record it under this lock_id
  #
  # periodically, try to acquire locks with pg_try_advisory_lock()
  # if we get the lock, we redistribute all processes to the appropriate node.
  # need to figure out what to do with the lock_id for each process.
  #
  # maybe this can be two processes running in parallel. first process: try selecting locks, if it gets one, simply clear the lock_id from the processes having this lock_id.
  # second process: select processes having no lock_id and see if you can own them, starting them and setting the lock on them when your select_node matches yourself.
  #
  # This might have the drawback that processes don't get shut down when the entire system reboots. But perhaps this is ok? I'm not sure. Maybe I can find a way to figure out when the entire cluster has shut down, and then clear processes that are not running.
  #
  # Perhaps if all locks can be acquired on boot, it simply truncates the table? Going to have to be careful of race conditions here. Maybe we have 1 lock to register, and in that way we can serialize registering. Then we can acquire the lock, check if we get all other locks, if that is the case, we truncate. Only after we register our own node lock, do we release the global lock. Race condition sorted!
  #
  # 1200 LOC Elixir.DynamicSupervisor (620 LOC of actual code). We will probably be copying most of that and then adding our own stuff on top.
end
