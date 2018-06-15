/**
Module selects manager singlethreated/multithreaded
 */
module mutils.job_manager.manager;

static if (1) {
	enum multithreadedManagerON = 1;
	public import mutils.job_manager.manager_multithreaded;
} else {
	enum multithreadedManagerON = 0;
	public import mutils.job_manager.manager_singlethreated;
}
public import mutils.job_manager.manager_utils;
public import mutils.job_manager.universal_delegate;
