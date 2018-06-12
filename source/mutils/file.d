module mutils.file;

import core.stdc.stdio : fclose, FILE, fopen, fread, fseek, ftell, fwrite, removeFileC=remove, SEEK_END, SEEK_SET;
import core.stdc.stdlib : free, malloc;
import std.algorithm : canFind;

import mutils.container.hash_map;
import mutils.container.vector;
import mutils.string;
import mutils.string : getTmpCString;

struct File{
	static long getModificationTimestamp(const(char)[] path){
		version(Posix){
			import core.sys.posix.sys.stat: stat, stat_t;
		}else version(Windows){
			import core.sys.windows.stat: stat, stat_t=struct_stat;
		}else{
			static assert(0);
		}
		auto tmpCString=getTmpCString(path);
		stat_t statbuf = void;
		int ok=stat(tmpCString.str.ptr, &statbuf);
		if(ok!=0){
			return -1;
		}
		return statbuf.st_mtime;
	}

	static bool exists(const(char)[] path){
		return File.getModificationTimestamp(path)!=-1;
	}

	static bool remove(const(char)[] path){
		char[1024] tmpBuff;
		auto tmpPath=getTmpCString(path, tmpBuff[]);
		return removeFileC(tmpPath.str.ptr)==0;
	}

	static ubyte[] rawRead(const(char)[] path){		
		char[1024] tmpBuff;
		auto tmpPath=getTmpCString(path, tmpBuff[]);
		FILE* f = fopen (tmpPath.str.ptr, "rb");
		if(f==null){
			return null;
		}		
		fseek (f, 0, SEEK_END);
		long length = ftell (f);
		fseek (f, 0, SEEK_SET);
		ubyte* buffer = cast(ubyte*)malloc (length);
		fread (buffer, 1, length, f);		
		fclose (f);
		
		return buffer[0..length];
	}

	static void rawRemoveReadedData(ubyte[] data){
		free(data.ptr);
	}

	static bool write(T)(const(char)[] path, const(T)[] data){
		static assert( is(T==ubyte) || is(T==char) );
		char[1024] tmpBuff;
		auto tmpPath=getTmpCString(path, tmpBuff[]);
		FILE* f = fopen ( tmpPath.str.ptr , "wb" );
		if(f is null){
			return false;
		}
		size_t elementsWritten=fwrite(data.ptr, data.length*T.sizeof, 1, f);
		fclose(f);
		return elementsWritten==1;
	}
	
}

unittest{
	long timestapm=File.getModificationTimestamp("source/");
}

struct FileWatcher{
	@disable this();
	private this(int){}
	@disable this(this);
	__gshared static FileWatcher instance=FileWatcher(1);

	alias EventDelegate=void delegate(string path, const ref WatchedFileInfo info);

	struct WatchedFileInfo{
		long timestamp;
		Vector!EventDelegate dels;
	}
	HashMap!(Vector!(char), WatchedFileInfo) watchedFiles;


	bool watchFile(const(char)[] path, EventDelegate del){
		long timestamp=File.getModificationTimestamp(path);
		WatchedFileInfo* info=&watchedFiles.getInsertDefault( Vector!(char)(cast(char[])path), WatchedFileInfo(timestamp) );
		info.timestamp=timestamp;
		if( !canFind(info.dels[], del) ){
			info.dels~=del;
		}
		return timestamp!=-1;
	}

	bool removeFileFromWatch(string path){
		return watchedFiles.tryRemove( Vector!(char)(cast(char[])path) );
	}

	bool removeFileFromWatch(string path, EventDelegate del){
		WatchedFileInfo noInfo=WatchedFileInfo(-1);
		WatchedFileInfo* info=&watchedFiles.getDefault( Vector!(char)(cast(char[])path), noInfo );
		if(info.timestamp==-1){
			return false;
		}
		return info.dels.tryRemoveElement(del);
	}

	void update(){
		foreach(ref Vector!char path, ref WatchedFileInfo info; &watchedFiles.byKeyValue){
			long timestamp=File.getModificationTimestamp(cast(string)path[]);
			if(info.timestamp==-1 && timestamp==-1){
				continue;
			}
			if(timestamp!=-1 && timestamp<=info.timestamp){
				continue;
			}
			info.timestamp=timestamp;
			foreach(del; info.dels){
				del(cast(string)path[], info);
			}
		}

	}
}

unittest{
	void watch(string path, const ref FileWatcher.WatchedFileInfo info){}
	FileWatcher.instance.watchFile("source/app.d", &watch);
	FileWatcher.instance.watchFile("source/app.d", &watch);
	FileWatcher.instance.watchFile("source/app.d", &watch);
	assert(FileWatcher.instance.watchedFiles.get(Vector!(char)(cast(char[])"source/app.d")).dels.length==1);
	FileWatcher.instance.update();
	FileWatcher.instance.removeFileFromWatch("source/app.d", &watch);
	FileWatcher.instance.removeFileFromWatch("source/app.d");
}