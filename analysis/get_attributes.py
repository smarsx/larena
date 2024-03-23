import json
import argparse
from eth_abi import encode


def main(args):
    with open(args.path) as f:
        x = json_to_obj(json.load(f))
        if args.type == "name":
            return x[args.type]
        elif args.type == "description":
            return x[args.type]
        elif args.type == "content":
            return x[args.type]
        elif args.type == "emissionMultiple":
            return encode_uint32(x[args.type])
        elif args.type == "status":
            return x[args.type]
        else:
            raise Exception("invalid type")


def json_to_obj(x):
    status = None
    ks = x.keys()
    attr = x["attributes"]
    content_key = "image" if "image" in ks else "animation_url"
    emissionMultiple = attr[0]["value"]
    if len(attr) > 1:
        status = attr[1]["value"]

    return {
        "name": x["name"],
        "description": x["description"],
        "content": x[content_key],
        "emissionMultiple": emissionMultiple,
        "status": status,
    }


def encode_uint32(resp):
    enc = encode(["uint32"], [int(resp)])
    ## append 0x for FFI parsing
    return "0x" + enc.hex()


def encode_string(resp):
    return str(resp)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "type", choices=["name", "description", "content", "emissionMultiple", "status"]
    )
    parser.add_argument("--path", type=str)
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    print(main(args))
