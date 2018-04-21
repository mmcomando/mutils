/**
Module which presents functionality to the user
 */
module job_manager;


public import mutils.job_manager.manager_utils:FiberData,getFiberData,multithreaded,callAndWait,callAndNothing;
public import mutils.job_manager.universal_delegate:makeUniversalDelegate;

private import mutils.job_manager.manager;
private import mutils.job_manager.manager_tests;

void startMainLoop(void function() mainLoop,uint threadsCount=0){
	jobManager.startMainLoop(mainLoop,threadsCount);
}
void resumeFiber(FiberData fiberData){
	jobManager.addFiber(fiberData);
}
void testMultithreated(){
	testScalability();
}