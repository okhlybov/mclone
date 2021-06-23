#include <stdio.h>
#include <errno.h>
#include <process.h>
#include <windows.h>

#define SZ 1024	

int main(int argc, char** argv, char** env) {
	int envc, i, s = strlen(argv[0]);
	while(argv[0][s] != '\\' && argv[0][s] != '/') --s;
	//--s; while(argv[0][s] != '\\' && argv[0][s] != '/') --s;
	argv[0][s] = '\0';
	// Force forward slash as a file name separator
	s = strlen(argv[0]);
	while(s >= 0) if(argv[0][s--] == '\\') argv[0][s+1] = '/';
	// Command line
	char* ruby = malloc(SZ*sizeof(char));
	snprintf(ruby, SZ, "%s/ruby/bin/ruby.exe", argv[0]);
	char* mclone = malloc(SZ*sizeof(char));
	snprintf(mclone, SZ, "%s/ruby/bin/mclone", argv[0]);
	char** _argv = malloc((argc+2)*sizeof(char*));
	i = 0;
	_argv[i++] = ruby;
	_argv[i++] = mclone;
	for(int x = 1; x < argc; ++x) _argv[i++] = argv[x];
	_argv[i] = NULL;
	// Environment
	for(envc = 0; env[envc]; ++envc);
	char* rclone = malloc(SZ*sizeof(char));
	snprintf(rclone, SZ, "RCLONE=%s/rclone/rclone.exe", argv[0]);
	char** _env = malloc((envc+2)*sizeof(char*));
	_env[i = 0] = rclone;
	for(int x = 0; x < envc; ++x) _env[++i] = env[x];
	_env[++i] = NULL;
	#ifndef NDEBUG
		printf("*** command line\n");
		for(int x = 0; _argv[x]; ++x) printf("%s ", _argv[x]);
		printf("\n");
		printf("*** environment\n");
		for(int x = 0; _env[x]; ++x) printf("%s\n", _env[x]);
	#endif
	return _spawnvpe(_P_WAIT, ruby, (const char* const*)_argv,  (const char* const*)_env);
};
