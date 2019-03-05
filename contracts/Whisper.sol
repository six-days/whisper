pragma solidity ^0.4.25;


contract Whisper {

    uint256 public constant DEDUCTPOINT = 100;  // 提成基数 %
    uint256 public constant DEDUCTPOST = 80;    //发布者占比
    uint256 public constant DEDUCTADMIN = 10;   //开发者占比
    uint256 public constant DEDUCTFEEDBACK = 10;    //反馈评论者占比
    uint256 public constant MINPAY = 0.0001 ether;  //最低支付数

    uint256 public adminProfit = 0; //开发团队待提取的分成
    uint256 public feedbackProfit = 0;  //反馈者的奖励池
    address public admin;   //合约所有者
    bool public secretOpen; //开放发布悄悄话
    bool public payOpen;    // 开放支付查看答案
    bool public whisperOpen;    //合约是否关闭
    
    struct Secret {
        bytes title;   //标题
        bytes description; //描述
        uint256 payAmount;  //支付的费用
        bool available; //消息是否可用
        address publisher;  //发布者地址
        uint256 publishTime;    //发布时间
        uint256 closeTime;  //截止时间
        uint256 payTimes;   //被购买的次数
    }

    Secret[]  public secrets;    //悄悄话列表

    mapping(uint256 => bytes) internal answer; //悄悄话的内容
    mapping(uint256 => bytes32[]) public tags;   //悄悄话的标签
    mapping(address => mapping(uint256 => uint256)) private userPays;   //用户支付的悄悄话，用户-id-支付时间
    mapping(address => mapping(uint256 => uint256)) private userFeedbacks;   //用户反馈，用户-id-反馈时间
    mapping(uint256 => uint256[2]) public feedback; //悄悄话的点赞和踩[攒个数,踩个数]

    // 新的悄悄话
    event NewSecret(
        uint256 indexed id,
        address indexed publisher,
        bytes title,
        uint256 publishTime,
        uint256 payAmount
    );

    // 支付查看悄悄话
    event PaySecret(
        uint256 indexed id,
        address indexed payUser,
        uint256 payTime
    );

    // 反馈
    event FeedBackSecret(
        uint256 indexed id,
        address indexed feedbackUser,
        uint256 feedbackTime,
        uint256 rewardAmount
    );

    //判断合约是否关闭
    modifier openWhisper {
        require(
            whisperOpen == true,
            "The secrets are closed at present"
        );
        _;
    }

    //判断是否开放发布
    modifier openSecret {
        require(
            secretOpen == true,
            "The secrets are closed at present"
        );
        _;
    }

    //判断是否开放支付查看
    modifier openPay {
        require(
            payOpen == true,
            "Pay closed at present"
        );
        _;
    }
    //判断是否是管理者
    modifier ownerOnly {
        require(
            admin == msg.sender,
            "Insufficient permissions"
        );
        _;
    }

    constructor(address ownerArg) public {
        admin = ownerArg;
        whisperOpen = true;
        secretOpen = true;
        payOpen = true;
    }

    function modifyNewSecret(bool _sw) public ownerOnly {
        require(secretOpen != _sw, "Nothing change");
        secretOpen = _sw;
    }

    function modifyPaySecret(bool _sw) public ownerOnly {
        require(payOpen != _sw, "Nothing change");
        payOpen = _sw;
    }
    
     //关闭开启合约
    function modifyWhisper(bool _ava) public ownerOnly {
        require(whisperOpen != _ava, "Nothing change");
        if (!_ava) {
            uint256 amount = feedbackProfit;
            feedbackProfit = 0;
            admin.transfer(amount); 
        }
        whisperOpen = _ava;
    }


    function modifyAdmin(address _admin) public ownerOnly {
        require(_admin != admin, "Set a new admin");
        admin = _admin;
    }

    //发布一个新的悄悄话
    function setNewSecret(bytes _title, bytes _desc, bytes _content, bytes32[] _tag,
        uint256 _coin, uint256 _closeTime) public openWhisper openSecret returns(bool success) {
        //_closeTime为0表示永不过期
        require(_closeTime == 0 || _closeTime > now, "Close time must be greater than the current time");       
        require(_coin >= MINPAY, "Pay is too low");
        require(_title.length > 0 && _title.length <= 60, "Title cannot be empty and less than 20 words");
        require(_content.length > 0 && _content.length < 1500, "Answer cannot be empty and less than 500 words");
        require(_desc.length < 1500, "Description less than 500 words");

        uint sid = secrets.length++;
        secrets[sid] = Secret({
            title : _title,
            description : _desc,
            payAmount : _coin,
            available : true,
            publisher : msg.sender,
            publishTime : now,
            closeTime : _closeTime,
            payTimes : 0
            });
        answer[sid] = _content;
        for (uint i=0; i<_tag.length; i++) {
            tags[sid].push(_tag[i]);
        }
        
        feedback[sid] = [0,0];

        emit NewSecret(sid, msg.sender, _title, now, _coin);
        return true;
    }

    //支付查看悄悄话
    function paySecret(uint256 _sid) public openWhisper openPay payable returns(bytes) {
        require(secrets.length > _sid, "Secret is not exist"); //验证是否存在该悄悄话
        Secret storage secret = secrets[_sid];
        require(secret.available == true, "Secret is not available"); //判断是否被关闭
        require(secret.closeTime == 0 || secret.closeTime > now, "Secret is closed"); //判断是否到期
        require(secret.payAmount <= msg.value, "Insufficient payment"); //判断支付的费用是否足够
        require(userPays[msg.sender][_sid] == 0, "You have pay this secret");
        // 计算发布者所得
        uint256 publisherReward = msg.value * DEDUCTPOST / DEDUCTPOINT;
        // 计算反馈奖励池所得
        uint256 feedbackReward = msg.value * DEDUCTFEEDBACK / DEDUCTPOINT;
        // 计算开发团队所得
        uint256 ownerReward = msg.value - publisherReward - feedbackReward;
        require(address(this).balance >= publisherReward, "not enough coin");
        feedbackProfit += feedbackReward;
        adminProfit += ownerReward;
        
        secret.publisher.transfer(publisherReward);

        userPays[msg.sender][_sid] = now;
        secret.payTimes += 1;   //购买次数加1

        emit PaySecret(_sid, msg.sender, now);

        return answer[_sid];
    }

    //对悄悄话进行反馈
    function feedBackSecret(uint256 _sid, bool _like) public openWhisper returns(bool success) {
        require(secrets.length > _sid, "Secret is not exist"); //验证是否存在该悄悄话
        Secret storage secret = secrets[_sid];
        require(secret.available == true, "Secret is not available"); //判断是否被关闭
        require(userPays[msg.sender][_sid] > 0, "Pay this secret First");   //验证是否购买过
        require(userFeedbacks[msg.sender][_sid] == 0, "You have like it");
        if(_like) {
            feedback[_sid][0] += 1; //点赞数加1
        }else{
            feedback[_sid][1] += 1; //点踩数加1
        }
        //获取反馈奖励，如果该悄悄话未有反馈，得奖励池的20%，否则得10%
        uint256 reward = 0;
        if(feedback[_sid][0] + feedback[_sid][1] == 1) {
            reward = feedbackProfit * 20 / DEDUCTPOINT;
        }else{
            reward = feedbackProfit * 10 / DEDUCTPOINT;
        }
        require(feedbackProfit > reward, "Not enough coin");
        feedbackProfit -= reward;
        userFeedbacks[msg.sender][_sid] = now;
        emit FeedBackSecret(_sid, msg.sender, now, reward);
        msg.sender.transfer(reward);
        return true;
    }

    //开发团队提取
    function withdrawAdminProfit() public ownerOnly {
        require(adminProfit > 0, "No adminProfit");
        uint256 amount = adminProfit;
        require(address(this).balance >= amount, "not enough money");
        adminProfit = 0;
        admin.transfer(amount);
    }

    //修改某个悄悄话关闭或打开
    function modifyOneSecret(uint256 _sid, bool _ava) public ownerOnly returns(bool) {
        require(secrets.length >= _sid, "Secret is not exist"); //验证是否存在该悄悄话
        Secret storage secret = secrets[_sid];
        require(secret.available != _ava, "Nothing change");
        secret.available = _ava;
    }
    
    //总悄悄话的数量
    function secretCount() public view returns(uint256) {
        return secrets.length;
    }
}
