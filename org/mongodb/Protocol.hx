package org.mongodb;

import haxe.Int32;
import haxe.Int64;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Output;
import haxe.io.Input;
import org.bsonspec.BSON;
import sys.net.Socket;
import sys.net.Host;

class Protocol
{
	public static function connect(?host:String = "localhost", ?port:Int = 27017)
	{
		socket = new Socket();
		socket.connect(new Host(host), port);
	}

	public static inline function message(msg:String)
	{
		throw "deprecated";
		var out:BytesOutput = new BytesOutput();
		out.writeString(msg);
		out.writeByte(0x00);

		request(OP_MSG, out.getBytes());
	}

	public static inline function query(collection:String, ?query:Dynamic, ?returnFields:Dynamic, skip:Int = 0, number:Int = 0)
	{
		var out:BytesOutput = new BytesOutput();
		out.writeInt32(Int32.ofInt(0)); // TODO: flags
		out.writeString(collection);
		out.writeByte(0x00); // string terminator
		out.writeInt32(Int32.ofInt(skip));
		out.writeInt32(Int32.ofInt(number));
		if (query == null) query = {};
		writeDocument(out, query);
		if (returnFields != null) {
			writeDocument(out, returnFields);
		}

		request(OP_QUERY, out.getBytes());
	}

	public static inline function getMore(collection:String, cursorId:Int64, number:Int = 0)
	{
		var out:BytesOutput = new BytesOutput();
		out.writeInt32(Int32.ofInt(0)); // reserved
		out.writeString(collection);
		out.writeByte(0x00); // string terminator
		out.writeInt32(Int32.ofInt(number));

		// write Int64
		out.writeInt32(Int64.getHigh(cursorId));
		out.writeInt32(Int64.getLow(cursorId));

		request(OP_GETMORE, out.getBytes());
	}

	public static inline function insert(collection:String, fields:Dynamic)
	{
		var out:BytesOutput = new BytesOutput();
		out.writeInt32(Int32.ofInt(0)); // TODO: flags
		out.writeString(collection);
		out.writeByte(0x00); // string terminator

		// write multiple documents, if an array
		if (Std.is(fields, Array))
		{
			var list = cast(fields, Array<Dynamic>);
			for (field in list)
			{
				writeDocument(out, field);
			}
		}
		else
		{
			writeDocument(out, fields);
		}

		// write request
		request(OP_INSERT, out.getBytes());
	}

	public static inline function update(collection:String, select:Dynamic, fields:Dynamic)
	{
		var out:BytesOutput = new BytesOutput();
		out.writeInt32(Int32.ofInt(0)); // reserved
		out.writeString(collection);
		out.writeByte(0x00); // string terminator
		out.writeInt32(Int32.ofInt(0)); // TODO: flags

		writeDocument(out, select);
		writeDocument(out, fields);

		// write request
		request(OP_UPDATE, out.getBytes());
	}

	public static inline function remove(collection:String, select:Dynamic)
	{
		var out:BytesOutput = new BytesOutput();
		out.writeInt32(Int32.ofInt(0)); // reserved
		out.writeString(collection);
		out.writeByte(0x00); // string terminator
		out.writeInt32(Int32.ofInt(0)); // TODO: flags
		writeDocument(out, select);

		request(OP_DELETE, out.getBytes());
	}

	public static inline function response(documents:Array<Dynamic>):Int64
	{
		var input = socket.input;
		input.readInt32(); // length
		input.readInt32(); // request id
		input.readInt32(); // response to
		input.readInt32(); // opcode
		var flags:Int32        = input.readInt32(); // flags
		var cursorId:Int64     = readInt64(input);
		var startingFrom:Int32 = input.readInt32();
		var numReturned:Int    = Int32.toNativeInt(input.readInt32());

		for (i in 0...numReturned)
		{
			documents.push(BSON.decode(input));
		}
		return cursorId;
	}

	private static inline function readInt64(input:Input):Int64
	{
		var high = input.readInt32();
		var low = input.readInt32();
		return Int64.make(high, low);
	}

	private static inline function request(opcode:Int, data:Bytes, ?responseTo:Int = 0):Int
	{
		if (socket == null)
		{
			throw "Not connected";
		}
		var out = socket.output;
		out.writeInt32(Int32.ofInt(data.length + 16)); // include header length
		out.writeInt32(Int32.ofInt(requestId));
		out.writeInt32(Int32.ofInt(responseTo));
		out.writeInt32(Int32.ofInt(opcode));
		out.writeBytes(data, 0, data.length);
		out.flush();
		return requestId++;
	}

	private static inline function writeDocument(out:BytesOutput, data:Dynamic)
	{
		var d = BSON.encode(data);
		out.writeBytes(d, 0, d.length);
	}

	private static var socket:Socket = null;
	private static var requestId:Int = 0;

	private inline static var OP_REPLY        = 1; // used by server
	private inline static var OP_MSG          = 1000; // not used
	private inline static var OP_UPDATE       = 2001;
	private inline static var OP_INSERT       = 2002;
	private inline static var OP_QUERY        = 2004;
	private inline static var OP_GETMORE      = 2005;
	private inline static var OP_DELETE       = 2006;
	private inline static var OP_KILL_CURSORS = 2007;
}