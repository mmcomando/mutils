/**
Module selects manager singlethreated/multithreated
 */
module mutils.job_manager.manager;

static if(1){
	enum multithreatedManagerON=1;
	public import mutils.job_manager.manager_multithreated;
}else{
	enum multithreatedManagerON=0;
	public import mutils.job_manager.manager_singlethreated;
}
public import mutils.job_manager.manager_utils; 
public import mutils.job_manager.universal_delegate; 