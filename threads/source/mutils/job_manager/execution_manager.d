module mutils.job_manager.execution_manager;

import mutils.container.vector;
import mutils.container_shared.shared_vector;

alias Delegate = void delegate();
class ExecutionManager {
	LockedVector!Delegate delegatesToExecute;
	void initialize() {
		delegatesToExecute = new LockedVector!Delegate();
	}

	void add(Delegate del) {
		delegatesToExecute.add(del);
	}

	void update() {
		Vector!Delegate delegates = delegatesToExecute.vectorCopyWithReset();
		//if(delegates is null)return;
		foreach (del; delegates) {
			del();
		}
	}

}
