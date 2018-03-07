pragma solidity ^0.4.17;

contract EcommerceStore {

	// 产品id
	uint public productIndex;
	// 发布者地址字典，记录每个钱包下发布了多少款产品
	// 二级字典记录产品ID => 产品结构体
	mapping(address => mapping(uint => Product)) stores;
	// 产品ID字典  产品ID => 发布者地址
	mapping(uint => address) productIdInstore;

	// 枚举，记录产品的拍卖状态
	enum ProductStatus {
		Open, // 0:拍卖中
		Sold, // 1:拍卖结束
		Unsold // 2:未开始
	}

	// 枚举，记录产品的新旧状态
	enum ProductCondition {
		New, // 0:新
		Used // 1:旧
	}

	// 产品结构体，记录产品所有属性
	struct Product {
		uint id; // 产品ID
		string name; // 产品名称
		string category; // 产品便签（分类）
		string imageLink; // 产品图片信息（存储在IPFS上的hash）
		string descLink; // 产品描述信息存在IPFS上的hash
		uint auctionStartTime; // 拍卖开始时间
		uint auctionEndTime; // 拍卖结束时间
		uint startPrice; // 起始拍卖价格
		address highestBidder; // 最高拍卖人地址
		uint highestBid; // 公告后最终统计出的最高价
		uint secondHighestBid; // 出价第二高的价格
		uint totalBids; // 参与竞价总人数
		ProductStatus status; // 拍卖状态
		ProductCondition condition; // 产品新旧
		// 该产品所有竞价人的信息字典
		// 竞价人的钱包地址 => {hash(出价+密钥) => 竞价信息}
		mapping(address => mapping(bytes32 => Bid)) bids;
	}
	
	// 竞价信息结构体
	struct Bid {
		address bidder; // 竞价人的钱包地址
		uint productId; // 产品ID
		uint value; // 填写的竞价价格（不一定是真实出价）
		bool revealed; // 是否公告
	}

	// 构造函数，初始化产品ID为0
	function EcommerceStore() public {
		productIndex = 0;
	}

	// 添加产品
	function addProductToStore(string _name, string _category, string _imageLink, string _descLink, uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition) public {
		// 验证：结束时间需大于开始时间
		require(_auctionStartTime < _auctionEndTime);
		// 产品ID累加
		productIndex += 1;
		// 得到产品实例
		Product memory product = Product(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, 0, 0, 0, 0, ProductStatus.Open, ProductCondition(_productCondition));
		// 记录当前发布者地址及产品至字典中
		stores[msg.sender][productIndex] = product;
		// 记录产品ID与添加者地址的对应关系
		productIdInstore[productIndex] = msg.sender;
	}

	// 通过ID读取产品信息
	function getProduct(uint _productId) view public returns(uint, string, string, string, string, uint, uint, uint, ProductStatus, ProductCondition) {
		// 通过产品ID取到创建者钱包地址，找到该地址下所有上传的产品，然后再通过产品ID得到指定的产品对象
		Product memory product = stores[productIdInstore[_productId]][_productId];
		// 返回产品所有信息
		return (product.id, product.name, product.category, product.imageLink, product.descLink, product.auctionStartTime, product.auctionEndTime, product.startPrice, product.status, product.condition);
	}

	// 投标。_productId：投标产品ID，_bid：投标值+密钥的hash
	// 涉及到真实的支付场景，需要加 payable 属性
	function bid(uint _productId, bytes32 _bid) payable public returns(bool) {
		// 获取产品信息
		Product storage product = stores[productIdInstore[_productId]][_productId];
		// 当前时间需在投标周期内
		require(now >= product.auctionStartTime);
		require(now <= product.auctionEndTime);
		// 竞价值需要大于最低价
		require(msg.value > product.startPrice);
		// 同一个钱包地址，相同的竞价信息（公开竞价值+密钥）只能发布一次
		require(product.bids[msg.sender][_bid].bidder == 0);
		// 当满足上述条件后，将该竞价者的信息存储，并扣除用户所公布数值的eth
		product.bids[msg.sender][_bid] = Bid(msg.sender, _productId, msg.value, false);
		// 总竞价人数 +1 
		product.totalBids += 1;
		// 参与竞价成功，如果不满足require条件返回false
		return true;
	}

	// 公告
	function revealBid(uint _productId, string _amount, string _secret) public {
		// 根据产品ID读取产品信息
		Product storage product = stores[productIdInstore[_productId]][_productId];
		// 公告需等产品拍卖结束后行
		require(now > product.auctionEndTime);
		// 通过公告的数值+密钥得到hash
		bytes32 sealedBid = sha3(_amount, _secret);
		// 通过hash找到公告人之前发布的竞价信息
		Bid memory bidInfo = product.bids[msg.sender][sealedBid];
		// 判断竞价信息中的实际竞价值是否大于0级该竞价是否已经公告过
		require(bidInfo.bidder > 0);
		require(bidInfo.revealed == false);

		// 需要给该用户返回多少钱
		uint refund;
		// 转换为solidity的uint类型
		uint amount = stringToUint(_amount);
		// 比较竞价时公布的值与实际竞价值，判断需返回给用户多少钱
		if(bidInfo.value < amount) {
			// 当公布值小于实际竞价值时，不符合竞标原则，全额退款
			refund = bidInfo.value;
		}else{
			// 如果最高竞价者地址为0，则当前竞价人为第一人
			// 由此该人的竞价值为最高，同时设定第二高的竞价值为产品的竞价起始值
			// 返回给给人的钱应该是 公布值-实际竞价值
			if(address(product.highestBidder) == 0) {
				product.highestBidder = msg.sender;
				product.secondHighestBid = amount;
				product.secondHighestBid = product.startPrice;
				//refund = bidInfo.value - amount;
				// 当前最高竞价者，如果最终中标，他最终所需支付的钱为第二高的价格，所以反还（竞价时所出价格-第二高价格）
				refund = bidInfo.value - product.secondHighestBid;
			}else{
				// 比较当前竞价者与竞价最高者、竞价第二高者的出资值
				// 根据比较结果修改相关信息
				if(amount > product.highestBid) {
					// 之前的最高竞价者失去竞争力，返还他所剩余的所有钱，也就是最高竞价值
					//product.highestBidder.transfer(product.highestBid);
					product.highestBidder.transfer(product.secondHighestBid);
					product.secondHighestBid = product.highestBid;
					// 最高竞价者的宝座让位给当前竞价者，并给他返回相应钱
					product.highestBidder = msg.sender;
					product.highestBid = amount;
					//refund = bidInfo.value - amount;
					refund = bidInfo.value - product.secondHighestBid;
				}else if(amount > product.secondHighestBid) {
					product.secondHighestBid = amount;
					//refund = amount;
					// 竞标失败，反还所有金额
					refund = bidInfo.value;
				}else {
					//refund = amount;
					refund = bidInfo.value;
				}
			}
			if(refund > 0) {
				// 反还代币，修改公告标识
				msg.sender.transfer(refund);
				product.bids[msg.sender][sealedBid].revealed = true;
			}
		}
	}

	/** 以下为工具类 */

	// 根据产品ID返回该产品的最高竞价值及最高竞价者钱包地址、第二高竞价值（中标者实际需要支付的数额）
	function highestBidderInfo(uint _productId) view public returns(address, uint, uint) {
		Product memory product = stores[productIdInstore[_productId]][_productId];
		return (product.highestBidder, product.highestBid, product.secondHighestBid);
	}

	// 返回指定产品的总参与竞价人数
	function totalBids(uint _productId) view public returns(uint) {
		Product memory product = stores[productIdInstore[_productId]][_productId];
		return product.totalBids;
	}

	// 将字符串转为uint类型
	function stringToUint(string s) pure private returns(uint) {
		bytes memory b = bytes(s);
		uint result = 0;
		for(uint i = 0; i < b.length; i++ ) {
			result = result * 10 + (uint(b[i]) - 48);
		}
		return result;
	}


}