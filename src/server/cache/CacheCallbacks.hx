package server.cache;

typedef CacheCallbacks = {
	/** Called once the final cache url is known, before download starts. **/
	final onResolved:(url:String) -> Void;
	final onProgress:(ratio:Float) -> Void;
	final onComplete:() -> Void;
	final onError:() -> Void;
	final ?registerCancel:(cancel:() -> Void) -> Void;
	/**
		Called when the real title/duration become known (for items added
		with a zero duration, e.g. when the client could not resolve them).
	**/
	final ?onMetadata:(title:Null<String>, duration:Float) -> Void;
}
