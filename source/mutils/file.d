module mutils.file;

import mutils.string;


struct File{
	static long getModificationTimestamp(string path){
		version(Posix){
			import core.sys.posix.sys.stat: stat, stat_t;
		}else version(Windows){
			import core.sys.windows.stat: stat, stat_t=struct_stat;
		}else{
			static assert(0);
		}
		auto tmpCString=getTmpCString(path);
		stat_t statbuf = void;
		stat(tmpCString.str.ptr, &statbuf);
		return statbuf.st_mtime;
	}
}

unittest{
	File.getModificationTimestamp("source/app.d");
}