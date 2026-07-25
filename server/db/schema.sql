-- MySQL dump 10.14  Distrib 5.5.64-MariaDB, for Linux (x86_64)
--
-- Host: localhost    Database: ReadingCoach
-- ------------------------------------------------------
-- Server version	5.5.64-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT COMMENT '用户唯一标识',
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '手机号码',
  `nickname` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '用户昵称',
  `avatar_url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '头像URL',
  `last_login_at` datetime DEFAULT NULL COMMENT '最后登录时间',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NULL DEFAULT NULL COMMENT '更新时间',
  PRIMARY KEY (`user_id`) USING BTREE,
  UNIQUE KEY `idx_phone` (`phone`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户基本信息表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'13800138000','用户8000',NULL,'2026-07-24 13:05:32','2025-09-26 09:46:39','2025-11-28 16:59:22'),(2,'13800138002','用户8002',NULL,'2025-09-29 11:13:01','2025-09-26 10:30:26','2025-09-29 11:13:01'),(3,'13800138005','用户8005',NULL,NULL,'2025-09-26 10:34:11','2025-09-26 10:34:11'),(4,'13800138007','用户8007',NULL,NULL,'2025-09-26 10:36:47','2025-09-26 10:36:47'),(5,'13800138009','用户8009',NULL,NULL,'2025-09-26 10:37:38','2025-09-26 10:37:38'),(6,'13800138010','用户8010',NULL,NULL,'2025-09-26 10:40:19','2025-09-26 10:40:19'),(7,'13800138001','用户8001',NULL,NULL,'2025-09-28 16:47:29','2025-09-28 16:47:29');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;

--
-- Table structure for table `verification_codes`
--

DROP TABLE IF EXISTS `verification_codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `verification_codes` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `phone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '手机号',
  `code` varchar(10) COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '验证码',
  `expires_at` datetime NOT NULL COMMENT '过期时间',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `used_at` timestamp NULL DEFAULT NULL COMMENT '使用时间',
  `is_used` tinyint(1) DEFAULT '0' COMMENT '是否已使用',
  `ip_address` varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '请求IP地址',
  `user_agent` text COLLATE utf8mb4_unicode_ci COMMENT '用户代理',
  PRIMARY KEY (`id`),
  KEY `idx_phone_expires` (`phone`,`expires_at`),
  KEY `idx_expires_at` (`expires_at`),
  KEY `idx_phone_created` (`phone`,`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=86 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='验证码表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `verification_codes`
--

/*!40000 ALTER TABLE `verification_codes` DISABLE KEYS */;
INSERT INTO `verification_codes` VALUES (85,'13800138000','253203','2026-07-24 13:08:30','2026-07-24 13:05:30','2026-07-24 13:05:32',1,NULL,NULL);
/*!40000 ALTER TABLE `verification_codes` ENABLE KEYS */;

--
-- Table structure for table `articles`
--

DROP TABLE IF EXISTS `articles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `articles` (
  `article_id` int(11) NOT NULL AUTO_INCREMENT COMMENT '文章ID（自增主键）',
  `user_id` int(11) NOT NULL COMMENT '用户ID（关联users表）',
  `title` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '文章标题',
  `sentence_count` int(11) NOT NULL DEFAULT '0' COMMENT '句子数量',
  `read_count` int(11) NOT NULL DEFAULT '0' COMMENT '阅读次数',
  `last_read_at` datetime DEFAULT NULL COMMENT '最后阅读时间',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NULL DEFAULT NULL COMMENT '更新时间',
  PRIMARY KEY (`article_id`),
  KEY `idx_user_id` (`user_id`) COMMENT '按用户查询',
  KEY `idx_last_read_at` (`user_id`,`last_read_at`) COMMENT '按用户和最后阅读时间排序',
  KEY `idx_created_at` (`created_at`) COMMENT '按创建时间排序'
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='文章表，存储用户上传的文章照片信息';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `articles`
--

/*!40000 ALTER TABLE `articles` DISABLE KEYS */;
INSERT INTO `articles` VALUES (13,1,'The memory',26,25,'2026-07-20 23:55:30','2026-07-20 13:46:35','2026-07-20 15:05:21'),(14,1,'Wikipedia vandals reliability',25,13,'2026-07-24 14:05:27','2026-07-20 23:52:13',NULL),(15,1,'Family Language Learning Benefits',18,3,'2026-07-22 02:22:08','2026-07-21 08:36:03',NULL),(18,1,'Mission Schools vs Bantu Education',22,1,'2026-07-23 13:44:37','2026-07-23 13:44:36',NULL),(19,1,'Music Benefits the Brain（综合一C篇）',16,3,'2026-07-24 13:05:39','2026-07-23 14:12:10','2026-07-23 14:39:51'),(20,1,'Cycling as networking tool(综合一D篇）',19,6,'2026-07-25 11:51:04','2026-07-23 14:38:52','2026-07-23 14:39:27'),(21,1,'Wikipedia reliability concerns',25,4,'2026-07-24 14:05:20','2026-07-24 13:05:55',NULL);
/*!40000 ALTER TABLE `articles` ENABLE KEYS */;

--
-- Table structure for table `article_sentences`
--

DROP TABLE IF EXISTS `article_sentences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `article_sentences` (
  `sentence_id` int(11) NOT NULL AUTO_INCREMENT COMMENT '句子ID（自增主键）',
  `article_id` int(11) NOT NULL COMMENT '文章ID（关联articles表）',
  `sentence_order` int(11) NOT NULL DEFAULT '0' COMMENT '句子顺序（从1开始）',
  `original_text` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '句子原文（英文）',
  `translation` text COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '中文翻译',
  `is_favorite` tinyint(1) NOT NULL DEFAULT '0' COMMENT '是否收藏（0=未收藏，1=已收藏）',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updated_at` timestamp NULL DEFAULT NULL COMMENT '更新时间',
  PRIMARY KEY (`sentence_id`),
  KEY `idx_article_id` (`article_id`) COMMENT '按文章查询',
  KEY `idx_sentence_order` (`article_id`,`sentence_order`) COMMENT '按文章和顺序查询',
  KEY `idx_is_favorite` (`article_id`,`is_favorite`) COMMENT '按文章和收藏状态查询'
) ENGINE=InnoDB AUTO_INCREMENT=296 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='文章句子表，存储每篇文章的句子信息';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `article_sentences`
--

/*!40000 ALTER TABLE `article_sentences` DISABLE KEYS */;
INSERT INTO `article_sentences` VALUES (123,13,1,'Most people hope to have a memory which helps them succeed in study, work and life.','大多数人希望拥有一种能帮助他们在学习、工作和生活中取得成功的记忆力。',0,'2026-07-20 13:46:35',NULL),(124,13,2,'Can memory be improved?','记忆力能提高吗？',0,'2026-07-20 13:46:35',NULL),(125,13,3,'Ludly, hundreds of studies in the past 50 years have already given us a definite answer.','幸运的是，过去50年中的数百项研究已经给了我们一个明确的答案。',0,'2026-07-20 13:46:35',NULL),(126,13,4,'A healthy lifestyle keeps your brain young and memory sharp.','健康的生活方式能让你的大脑保持年轻，记忆力保持敏锐。',0,'2026-07-20 13:46:35',NULL),(127,13,5,'First of all, it is necessary to have a healthy diet.','首先，保持健康的饮食是必要的。',0,'2026-07-20 13:46:35','2026-07-20 14:23:55'),(128,13,6,'Eating more food rich in Vitamin B and Vitamin E, such as vegetables and lean meat, helps you have a better memory.','多吃富含维生素B和维生素E的食物，比如蔬菜和瘦肉，有助于你拥有更好的记忆力。',0,'2026-07-20 13:46:35',NULL),(129,13,7,'Doing exercise can keep your brain alive, too.','做运动也能让你的大脑保持活跃。',0,'2026-07-20 13:46:35',NULL),(130,13,8,'Proper exercise provides much needed oxygen for the brain.','适当的运动为大脑提供急需的氧气。',0,'2026-07-20 13:46:35',NULL),(131,13,9,'Running, riding a bike, swimming and even walking two or three times a week are helpful.','跑步、骑自行车、游泳，甚至每周散步两到三次，都很有帮助。',0,'2026-07-20 13:46:35',NULL),(132,13,10,'Moreover, getting enough sleep is important.','此外，获得充足的睡眠很重要。',0,'2026-07-20 13:46:35',NULL),(133,13,11,'Only when your brain gets a good rest, can it work well.','只有当你的大脑得到充分休息时，它才能良好运作。',0,'2026-07-20 13:46:35',NULL),(134,13,12,'The healthier your lifestyle is, the better your memory will become, but do not expect a sudden change — it takes a long time to make a difference.','你的生活方式越健康，你的记忆力就会越好，但不要期待突然的改变——产生效果需要很长时间。',0,'2026-07-20 13:46:35',NULL),(135,13,13,'Memory skills help you remember things better.','记忆技巧能帮助你更好地记住事物。',0,'2026-07-20 13:46:35',NULL),(136,13,14,'The following three are the most widely used.','以下三种是最广泛使用的。',0,'2026-07-20 13:46:35',NULL),(137,13,15,'Chunking is a way of remembering a piece of information by cutting it into smaller ones.','分块是一种通过将一条信息切分成更小部分来记忆的方法。',0,'2026-07-20 13:46:35',NULL),(138,13,16,'For example, to memorize a ten-digit telephone number 2127983630, you can divide the digits into three groups: first 212, then 798, and lastly 3630.','例如，要记住一个十位电话号码2127983630，你可以将这些数字分成三组：先是212，然后是798，最后是3630。',0,'2026-07-20 13:46:35',NULL),(139,13,17,'This method is far more effective than remembering a string of 10 digits.','这种方法比记住一串10个数字有效得多。',0,'2026-07-20 13:46:35',NULL),(140,13,18,'Organization means organizing information into groups of the same kind.','组织意味着将信息归类为同一类别的组。',0,'2026-07-20 13:46:35',NULL),(141,13,19,'For example, trees, grass and flowers are plants; tigers, pandas, horses and cows are animals.','例如，树木、草和花是植物；老虎、熊猫、马和牛是动物。',0,'2026-07-20 13:46:35',NULL),(142,13,20,'Imagery is remembering newly learnt information by using your imagination and connecting it with something that you are familiar with.','意象法是通过运用想象力，将新学信息与你熟悉的事物联系起来进行记忆。',0,'2026-07-20 13:46:35',NULL),(143,13,21,'However, memory skills will hardly work if you don\'t understand the information.','然而，如果你不理解信息，记忆技巧几乎不会起作用。',0,'2026-07-20 13:46:35',NULL),(144,13,22,'Only a regular review can make the memory last long.','只有定期复习才能让记忆持久。',0,'2026-07-20 13:46:35',NULL),(145,13,23,'That is why students are always advised to go over what they have learnt after one day and then after three days, and then use it as regularly as possible.','这就是为什么总是建议学生在一天后复习所学内容，然后在三天后再复习，并尽可能规律地使用它。',0,'2026-07-20 13:46:35',NULL),(146,13,24,'Human brains are like muscles that need nutrients and exercise to become stronger.','人脑就像肌肉一样，需要营养和锻炼才能变得更强壮。',0,'2026-07-20 13:46:35',NULL),(147,13,25,'If you make a few lifestyle changes and try some memory skills, you can certainly improve your memory.','如果你在生活方式上做一些改变，并尝试一些记忆技巧，你肯定能提高记忆力。',0,'2026-07-20 13:46:35',NULL),(148,13,26,'37. What does proper exercise provide the brain?','37. 适当的运动为大脑提供什么？',0,'2026-07-20 13:46:35',NULL),(149,14,1,'What do you do when you need to look something up?','当你需要查资料时会怎么做？',0,'2026-07-20 23:52:13',NULL),(150,14,2,'Go to the library? Open an encyclopaedia? Click on to the internet?','去图书馆？翻开百科全书？还是上网搜索？',0,'2026-07-20 23:52:13',NULL),(151,14,3,'These days, most people go straight to Wikipedia, the online encyclopaedia.','如今，大多数人直接使用在线百科全书维基百科。',0,'2026-07-20 23:52:13',NULL),(152,14,4,'But how reliable is it?','但它有多可靠呢？',0,'2026-07-20 23:52:13',NULL),(153,14,5,'There\'s no denying the popularity and usefulness of Wikipedia.','不可否认维基百科的受欢迎程度和实用性。',0,'2026-07-20 23:52:13',NULL),(154,14,6,'It attracts 78 million visitors every month, and the site is available in more than 270 different languages.','它每月吸引7800万访客，并提供超过270种语言版本。',0,'2026-07-20 23:52:13',NULL),(155,14,7,'It\'s one of the most comprehensive resources available, and it\'s got much more information than an ordinary encyclopaedia.','它是现有最全面的资源之一，信息量远超普通百科全书。',0,'2026-07-20 23:52:13',NULL),(156,14,8,'The site is updated on a daily basis by thousands of people around the world.','全球数千人每天更新网站内容。',0,'2026-07-20 23:52:13',NULL),(157,14,9,'Anyone with an internet connection can log on and edit the contents or add a new page.','任何能上网的人都可以登录编辑内容或添加新页面。',0,'2026-07-20 23:52:13',NULL),(158,14,10,'And you don\'t need any formal training.','而且你不需要任何正式培训。',0,'2026-07-20 23:52:13',NULL),(159,14,11,'Of course, there are some controls.','当然，也有一些管控措施。',0,'2026-07-20 23:52:13',NULL),(160,14,12,'Wikipedia has a team of more than 1,500 administrators who check for false information.','维基百科有超过1500名管理员负责核查虚假信息。',0,'2026-07-20 23:52:13',NULL),(161,14,13,'And prime targets for malicious comments (such as politicians) are off-limits to public editing.','恶意评论的主要目标（如政客）禁止公众编辑。',0,'2026-07-20 23:52:13',NULL),(162,14,14,'But with more than 16 million articles to keep an eye on, it isn\'t easy.','但监控超过1600万篇文章并不容易。',0,'2026-07-20 23:52:13',NULL),(163,14,15,'So, while Wikipedia benefits from being constantly updated with information from all over the world, it\'s also open to \"vandals\".','因此，维基百科虽得益于全球信息的持续更新，但也对“破坏者”敞开大门。',0,'2026-07-20 23:52:13',NULL),(164,14,16,'Some of the damage is easy to notice.','有些破坏行为很容易被发现。',0,'2026-07-20 23:52:13',NULL),(165,14,17,'One prankster drew devil horns and a moustache on Microsoft chairman Bill Gates\'s photo, while another edited Greek philosopher Plato\'s biography to say he was a \"Hawaiian weather man\".','一个恶作剧者在微软董事长比尔·盖茨的照片上画了恶魔角和胡子，另一个则将希腊哲学家柏拉图的生平改为“夏威夷天气预报员”。',0,'2026-07-20 23:52:13',NULL),(166,14,18,'But other things are harder to spot.','但其他破坏则更难察觉。',0,'2026-07-20 23:52:13',NULL),(167,14,19,'The most common form of vandalism involves adding tiny items of false information into the biography of a famous person.','最常见的破坏形式是在名人传记中添加细微的虚假信息。',0,'2026-07-20 23:52:13',NULL),(168,14,20,'Some of this misinformation has even appeared in newspapers, with The Daily Mail, The Guardian and The Independent all having fallen victim to the pranks.','部分虚假信息甚至出现在报纸上，《每日邮报》《卫报》和《独立报》都曾中招。',0,'2026-07-20 23:52:13',NULL),(169,14,21,'For example, in an obituary for British comedian Sir Norman Wisdom, one newspaper claimed that he co-wrote Dame Vera Lynn\'s wartime hit \"There\'ll be Bluebirds over the White Cliffs of Dover\".','例如，在英国喜剧演员诺曼·威斯登爵士的讣告中，一家报纸称他与维拉·琳恩女爵士合写了战时热门歌曲《白崖上有蓝鸟》。',0,'2026-07-20 23:52:13',NULL),(170,14,22,'He did no such thing.','他根本没做过这事。',0,'2026-07-20 23:52:13',NULL),(171,14,23,'And in another article, it was reported that TV theme tune composer Ronnie Hazlehurst had written the S Club 7 hit \"Reach\".','另一篇文章则报道电视主题曲作曲家罗尼·黑泽尔赫斯特创作了S Club 7的热门歌曲《Reach》。',0,'2026-07-20 23:52:13',NULL),(172,14,24,'Once again, not true.','同样，这不是真的。',0,'2026-07-20 23:52:13',NULL),(173,14,25,'So, if you\'re going to use any information from Wikipedia, make sure you double-check it first.','因此，如果你要使用维基百科的任何信息，务必先仔细核实。',0,'2026-07-20 23:52:13',NULL),(174,15,1,'Ever thought of making language learning part of your family\'s activities?','有没有想过让语言学习成为家庭活动的一部分？',0,'2026-07-21 08:36:03',NULL),(175,15,2,'Learning a new language together can have unexpected emotional benefits for the whole family.','一起学习一门新语言能给整个家庭带来意想不到的情感益处。',0,'2026-07-21 08:36:03',NULL),(176,15,3,'Combining family time and language learning time is a great way to have more quality time with your family.','把家庭时间和语言学习时间结合起来，是增加高质量家庭时光的好方法。',0,'2026-07-21 08:36:03',NULL),(177,15,4,'Learning a new language as a family can be a fun group activity.','全家一起学习一门新语言可以是一项有趣的集体活动。',0,'2026-07-21 08:36:03',NULL),(178,15,5,'Everyone loves a game night or movie night.','每个人都喜欢游戏之夜或电影之夜。',0,'2026-07-21 08:36:03',NULL),(179,15,6,'You can play games like Bingo, using vocabulary from the target language.','你可以玩像宾果这样的游戏，使用目标语言的词汇。',0,'2026-07-21 08:36:03',NULL),(180,15,7,'Or maybe you have a particular vacation destination you love where another language is widely spoken — learning that language together could make your next vacation even more enjoyable.','或者你有一个特别喜欢的度假目的地，那里广泛使用另一种语言——一起学习那种语言能让你的下一次假期更加愉快。',0,'2026-07-21 08:36:03',NULL),(181,15,8,'They\'re a fun way to break up the daily routine and reconnect with those you love.','它们是打破日常惯例、重新与你所爱的人建立联系的有趣方式。',0,'2026-07-21 08:36:03',NULL),(182,15,9,'Language is all about communication and connection.','语言关乎沟通和联系。',0,'2026-07-21 08:36:03',NULL),(183,15,10,'Learning a new language brings family members closer because they talk to each other all the time when learning.','学习一门新语言能让家庭成员更亲近，因为他们在学习过程中一直互相交流。',0,'2026-07-21 08:36:03',NULL),(184,15,11,'All you have to do is to change to your new language and practice with your family members whenever you want — no classroom needed.','你只需切换到新语言，随时与家人练习——不需要教室。',0,'2026-07-21 08:36:03',NULL),(185,15,12,'Telling family stories with what you have recently learned is a good place to start, which could inspire questions and additional conversations, and even create a familect — secret words and phrases shared only among the members of your family.','用你最近学到的内容讲述家庭故事是一个好的开始，这能激发问题和更多对话，甚至创造一种家庭语言——只有家庭成员共享的秘密词汇和短语。',0,'2026-07-21 08:36:03',NULL),(186,15,13,'If your family is big on gardening, make labels together for your plants and tools.','如果你的家庭热衷于园艺，一起为植物和工具制作标签。',0,'2026-07-21 08:36:03',NULL),(187,15,14,'Making fun labels in your target language together can also help you connect with loved family members.','一起用目标语言制作有趣的标签也能帮助你与亲爱的家人建立联系。',0,'2026-07-21 08:36:03',NULL),(188,15,15,'It opens up more opportunities like family contests.','这开启了更多机会，比如家庭竞赛。',0,'2026-07-21 08:36:03',NULL),(189,15,16,'You could surprise each other with notes on pillows, bathroom mirrors, inside dresser drawers — any place your family will find them.','你们可以在枕头上、浴室镜子上、梳妆台抽屉里——任何家人会发现的地方——用便条给彼此惊喜。',0,'2026-07-21 08:36:03',NULL),(190,15,17,'Using these words later recalls these family memories.','之后使用这些词汇会唤起这些家庭回忆。',0,'2026-07-21 08:36:03',NULL),(191,15,18,'Language learning lies in its ability to draw people together.','语言学习在于它能把人们凝聚在一起的能力。',0,'2026-07-21 08:36:03',NULL),(214,18,1,'Before apartheid, any black South African who received a formal education was likely taught by European missionaries, foreign enthusiasts eager to Christianize and Westernize the natives.','在种族隔离制度之前，任何接受正规教育的南非黑人很可能由欧洲传教士教导，这些外国热心者急于使当地人基督教化和西方化。',0,'2026-07-23 13:44:36',NULL),(215,18,2,'In the mission schools, black people learned English, European literature, medicine, the law.','在教会学校里，黑人学习英语、欧洲文学、医学和法律。',0,'2026-07-23 13:44:36',NULL),(216,18,3,'It\'s no coincidence that nearly every major black leader of the anti-apartheid movement was educated by the missionaries - a knowledgeable man is a free man, or at least a man who longs for freedom.','反种族隔离运动的几乎所有主要黑人领袖都由传教士教育并非巧合——一个有知识的人是自由的人，或至少是一个渴望自由的人。',0,'2026-07-23 13:44:36',NULL),(217,18,4,'The only way to make apartheid work, therefore, was to cripple the black mind.','因此，使种族隔离制度奏效的唯一方法就是摧残黑人的思想。',0,'2026-07-23 13:44:36',NULL),(218,18,5,'Under apartheid, the government built what became known as Bantu schools.','在种族隔离制度下，政府建立了所谓的班图学校。',0,'2026-07-23 13:44:36',NULL),(219,18,6,'Bantu schools taught no science, no history, no civics.','班图学校不教科学、历史或公民学。',0,'2026-07-23 13:44:36',NULL),(220,18,7,'They taught metrics and agriculture: how to count potatoes, how to pave roads, chop wood, till the soil.','他们教授度量衡和农业：如何数土豆、如何铺路、劈柴、耕地。',0,'2026-07-23 13:44:36',NULL),(221,18,8,'\"It does not serve the Bantu to learn history and science because he is primitive,\" the government said.','“班图人学习历史和科学没有用，因为他是原始的，”政府说。',0,'2026-07-23 13:44:36',NULL),(222,18,9,'\"This will only mislead him, showing him pastures in which he is not allowed to graze.\"','“这只会误导他，向他展示他不被允许放牧的牧场。”',0,'2026-07-23 13:44:36',NULL),(223,18,10,'To their credit, they were simply being honest.','公平地说，他们只是坦诚相告。',0,'2026-07-23 13:44:36',NULL),(224,18,11,'Why educate a slave? Why teach someone Latin when his only purpose is to dig holes in the ground?','为什么要教育奴隶？当一个人的唯一目的是在地上挖洞时，为什么要教他拉丁语？',0,'2026-07-23 13:44:36',NULL),(225,18,12,'Mission schools were told to conform to the new curriculum or shut down.','教会学校被告知要么遵守新课程，要么关闭。',0,'2026-07-23 13:44:36',NULL),(226,18,13,'Most of them shut down, and black children were forced into crowded classrooms in dilapidated schools, often with teachers who were barely literate themselves.','大多数学校关闭了，黑人儿童被迫进入破旧学校拥挤的教室，教师往往自己几乎不识字。',0,'2026-07-23 13:44:36',NULL),(227,18,14,'Our parents and grandparents were taught with little singsong lessons, the way you\'d teach a preschooler shapes and to sing the songs and laugh about how silly they were.','我们的父母和祖父母接受的是简单的唱歌式课程，就像你教幼儿形状和唱歌一样，并嘲笑它们多么愚蠢。',0,'2026-07-23 13:44:36',NULL),(228,18,15,'Two times two is four. Three times two is six. La la la la la.','二乘二等于四。三乘二等于六。啦啦啦啦啦。',0,'2026-07-23 13:44:36',NULL),(229,18,16,'We\'re talking about fully grown teenagers being taught this way, for generations.','我们说的是完全成年的青少年被这样教导，持续了几代人。',0,'2026-07-23 13:44:36',NULL),(230,18,17,'What happened with education in South Africa, with the mission schools and the Bantu schools, offers a neat comparison of the two groups of whites who oppressed us, the British and the Afrikaners.','南非教育中教会学校和班图学校所发生的事，提供了一个对压迫我们的两组白人——英国人和阿非利卡人——的清晰比较。',0,'2026-07-23 13:44:36',NULL),(231,18,18,'The difference between British racism and Afrikaner racism was that at least the British gave the natives something to aspire to.','英国种族主义和阿非利卡种族主义的区别在于，至少英国人给了当地人一些可以向往的东西。',0,'2026-07-23 13:44:36',NULL),(232,18,19,'If they could learn to speak correct English and dress in proper clothes, if they could Anglicize and civilize themselves, one day they might be welcome in society.','如果他们能学会说正确的英语并穿着得体的衣服，如果他们能英国化和文明化自己，有一天他们可能会在社会中受到欢迎。',0,'2026-07-23 13:44:36',NULL),(233,18,20,'The Afrikaners never gave us that option.','阿非利卡人从未给我们那个选择。',0,'2026-07-23 13:44:36',NULL),(234,18,21,'British racism said, \"If the monkey can walk like a man and talk like a man, then perhaps he is a man.\"','英国种族主义说：“如果猴子能像人一样走路和说话，那么也许他就是人。”',0,'2026-07-23 13:44:36',NULL),(235,18,22,'Afrikaner racism said, \"Why give a book to a monkey?\"','阿非利卡种族主义说：“为什么要把书给猴子？”',0,'2026-07-23 13:44:36',NULL),(236,19,1,'In all the world\'s cultures, people sing, play instruments, and celebrate with music.','在世界所有文化中，人们唱歌、演奏乐器并用音乐庆祝。',0,'2026-07-23 14:12:10',NULL),(237,19,2,'It is an important part of our lives.','它是我们生活的重要组成部分。',0,'2026-07-23 14:12:10',NULL),(238,19,3,'Scientists are finding that learning to play an instrument or just listening to music can do us good in many ways.','科学家发现，学习演奏乐器或仅仅听音乐都能在许多方面对我们有益。',0,'2026-07-23 14:12:10',NULL),(239,19,4,'Learning to play an instrument can help children improve math, science, and language skills.','学习演奏乐器可以帮助孩子提高数学、科学和语言技能。',0,'2026-07-23 14:12:10',NULL),(240,19,5,'One study in Canada found out that children who studied music had the biggest test grade improvements.','加拿大的一项研究发现，学习音乐的孩子考试成绩提升最大。',0,'2026-07-23 14:12:10',NULL),(241,19,6,'The secret may be in the way reading music and playing notes on an instrument uses some parts of the brain, which improves our ability to learn school subjects.','秘诀可能在于读谱和演奏乐器时大脑某些部分被激活，从而提高了我们学习学校科目的能力。',0,'2026-07-23 14:12:10',NULL),(242,19,7,'Music is also used for improving memory.','音乐也被用于改善记忆力。',0,'2026-07-23 14:12:10',NULL),(243,19,8,'An old song can help you remember something that happened years ago.','一首老歌能帮你回忆起多年前发生的事情。',0,'2026-07-23 14:12:10',NULL),(244,19,9,'For people with Alzheimer\'s, listening to music can help them remember their lost memories.','对于阿尔茨海默病患者，听音乐能帮助他们找回失去的记忆。',0,'2026-07-23 14:12:10',NULL),(245,19,10,'Studies of the music often center on classical music, since it makes both the left and right sides of our brains more active.','对音乐的研究常集中于古典音乐，因为它能使我们大脑的左右两侧都更加活跃。',0,'2026-07-23 14:12:10',NULL),(246,19,11,'One study found that activity was highest during the short breaks between the movements of a piece of music.','一项研究发现，在一首乐曲的乐章之间的短暂间歇中，大脑活动最为活跃。',0,'2026-07-23 14:12:10',NULL),(247,19,12,'During each break, the person\'s brain tried to work out what would come next, while organizing what he or she had just heard.','在每个间歇中，人的大脑会试图推测接下来会发生什么，同时整理刚刚听到的内容。',0,'2026-07-23 14:12:10',NULL),(248,19,13,'It\'s amazing how attuned our brains are to music.','我们的大脑对音乐如此敏感，真是令人惊叹。',0,'2026-07-23 14:12:10',NULL),(249,19,14,'Some scientists even think we\'re born with the ability to learn music, just as we all have the skills to learn language.','一些科学家甚至认为我们天生就有学习音乐的能力，就像我们都有学习语言的技能一样。',0,'2026-07-23 14:12:10',NULL),(250,19,15,'After all, children without any training often make up songs while they play.','毕竟，未经任何训练的孩子在玩耍时也常常编唱歌曲。',0,'2026-07-23 14:12:10',NULL),(251,19,16,'People are coming to know that more than just a kind of enjoyment, music is also great for the brain.','人们逐渐认识到，音乐不仅仅是一种享受，对大脑也大有裨益。',0,'2026-07-23 14:12:10',NULL),(252,20,1,'Traditionally, business people would get to know each other over a round of golf.','传统上，商务人士会通过一场高尔夫球来相互了解。',0,'2026-07-23 14:38:52',NULL),(253,20,2,'But road cycling is fast catching up as the preferred way of networking recently.','但公路自行车最近正迅速成为首选的社交方式。',0,'2026-07-23 14:38:52',NULL),(254,20,3,'\"When you play golf with somebody, you have to decide if you\'re going in beat them, or let them beat you,\" says Peter Murray, a chairman of the NLA centre.','NLA中心主席彼得·默里说：“当你和别人打高尔夫时，你必须决定是要打败他们，还是让他们打败你。”',0,'2026-07-23 14:38:52',NULL),(255,20,4,'\"If they\'re your customers and you don\'t want to beat them, sometimes you might have to make some kind of cheating in order to lose. That seems to me not a good way of doing things.\"','“如果他们是你的客户，你不想打败他们，有时你可能得耍点花招才能输掉。在我看来，这不是一种好的做事方式。”',0,'2026-07-23 14:38:52',NULL),(256,20,5,'\"Group cycling, and especially long-distance riding, is a shared experience,\" Mr. Murray says.','默里先生说：“团体骑行，尤其是长途骑行，是一种共享的经历。”',0,'2026-07-23 14:38:52',NULL),(257,20,6,'Riders often work together and help each other out, taking turns to be at the front so that the riders in their group can save almost a third of the effort.','骑手们经常互相合作、互相帮助，轮流领骑，这样团队中的骑手可以节省近三分之一的体力。',0,'2026-07-23 14:38:52',NULL),(258,20,7,'“How someone rides a bike can give you a real insight into what a person is like,\" says Jean-Jacques Lorraine, founding director of Morrow Lorraine, a team member of Cycle to Cannes.','“一个人如何骑自行车能让你真正了解他的为人，”让-雅克·洛林说，他是Morrow Lorraine的创始董事，也是“骑行去戛纳”团队的成员。',0,'2026-07-23 14:38:52',NULL),(259,20,8,'\"Some riders are very single-minded, others more collaborative; some are skillful, others an open book.\"','“有些骑手非常专注，另一些则更善于合作；有些人技术娴熟，有些人则一目了然。”',0,'2026-07-23 14:38:52',NULL),(260,20,9,'\"If I walk into a meeting and somebody says I\'ve done Cycle to Cannes\', it\'s a done deal really,\" says Mr. Lorraine.','洛林先生说：“如果我走进一个会议，有人说‘我参加过骑行去戛纳’，那基本上就成交了。”',0,'2026-07-23 14:38:52',NULL),(261,20,10,'Mr. Mottram, CEO of Rapha, believes it is easier to get to know people by cycling than in other situations.','Rapha的首席执行官莫特拉姆先生认为，通过骑行认识人比其他场合更容易。',0,'2026-07-23 14:38:52',NULL),(262,20,11,'\"I feel open and honest to others.\"','“我对他人感到开放和诚实。”',0,'2026-07-23 14:38:52',NULL),(263,20,12,'Mr. Lorraine makes the point more directly: \"I often find I\'m saying things on a bike which I wouldn\'t normally say, and equally I\'ve been confided in when I wasn\'t expecting it.\"','洛林先生更直接地指出：“我经常发现自己在自行车上说一些平时不会说的话，同样，我也在毫无预料的情况下听到别人的秘密。”',0,'2026-07-23 14:38:52',NULL),(264,20,13,'Why do cycle rides lend riders so well to networking?','为什么骑行如此适合社交？',0,'2026-07-23 14:38:52',NULL),(265,20,14,'\"Getting a quick lunch or drink after work doesn\'t give you long enough to get to know someone,\" Mr. Murray says.','默里先生说：“下班后快速吃个午饭或喝一杯，时间不够长，不足以了解一个人。”',0,'2026-07-23 14:38:52',NULL),(266,20,15,'He believes long rides get people together.','他认为长途骑行能让人们聚在一起。',0,'2026-07-23 14:38:52',NULL),(267,20,16,'\"A younger rider can be cycling along with a boss and help him in some way and you get a reversal of the relationship. This changes the relationship when they are off the ride too.\"','“一个年轻的骑手可以和老板一起骑行，并以某种方式帮助他，这样你们的关系就发生了逆转。这也会改变他们骑行之外的关系。”',0,'2026-07-23 14:38:52',NULL),(268,20,17,'Perhaps the main reason why cycling is a good way to network is that it\'s a passion and a way of life.','也许骑行是一种很好的社交方式的主要原因在于它是一种热情和一种生活方式。',0,'2026-07-23 14:38:52',NULL),(269,20,18,'\"Getting out on the bike is what we\'re all dreaming of doing while we\'re sitting at our computers,\" says Mr Mottram.','莫特拉姆先生说：“当我们坐在电脑前时，骑上自行车是我们都梦想做的事情。”',0,'2026-07-23 14:38:52',NULL),(270,20,19,'And a shared passion is a fantastic way to start any relationship.','而共同的热情是开启任何关系的绝佳方式。',0,'2026-07-23 14:38:52',NULL),(271,21,1,'What do you do when you need to look something up?','当你需要查找某样东西时，你会怎么做？',0,'2026-07-24 13:05:55',NULL),(272,21,2,'Go to the library? Open an encyclopedia? Click on to the internet?','去图书馆？打开百科全书？上网搜索？',0,'2026-07-24 13:05:55',NULL),(273,21,3,'These days, most people go straight to Wikipedia, the online encyclopedia.','如今，大多数人直接使用在线百科全书维基百科。',0,'2026-07-24 13:05:55',NULL),(274,21,4,'But how reliable is it?','但它有多可靠呢？',0,'2026-07-24 13:05:55',NULL),(275,21,5,'There\'s no denying the popularity and usefulness of Wikipedia.','不可否认维基百科的受欢迎程度和实用性。',0,'2026-07-24 13:05:55',NULL),(276,21,6,'It attracts 78 million visitors every month, and the site is available in more than 270 different languages.','它每月吸引7800万访客，并提供超过270种语言版本。',0,'2026-07-24 13:05:55',NULL),(277,21,7,'It\'s one of the most comprehensive resources available, and it\'s got much more information than an ordinary encyclopedia.','它是现有最全面的资源之一，信息量远超普通百科全书。',0,'2026-07-24 13:05:55',NULL),(278,21,8,'The site is updated on a daily basis by thousands of people around the world.','该网站由全球数千人每日更新。',0,'2026-07-24 13:05:55',NULL),(279,21,9,'Anyone with an internet connection can log on and edit the contents or add a new page.','任何能上网的人都可以登录并编辑内容或添加新页面。',0,'2026-07-24 13:05:55',NULL),(280,21,10,'And you don\'t need any formal training.','而且你不需要任何正式培训。',0,'2026-07-24 13:05:55',NULL),(281,21,11,'Of course, there are some controls.','当然，也有一些管控措施。',0,'2026-07-24 13:05:55',NULL),(282,21,12,'Wikipedia has a team of more than 1,500 administrators who check for false information.','维基百科有超过1500名管理员组成的团队负责核查虚假信息。',0,'2026-07-24 13:05:55',NULL),(283,21,13,'And prime targets for malicious comments (such as politicians) are off-limits to public editing.','恶意评论的主要目标（如政客）禁止公众编辑。',0,'2026-07-24 13:05:55',NULL),(284,21,14,'But with more than 16 million articles to keep an eye on, it isn\'t easy.','但要监控超过1600万篇文章并不容易。',0,'2026-07-24 13:05:55',NULL),(285,21,15,'So, while Wikipedia benefits from being constantly updated with information from all over the world, it\'s also open to \"vandals.\"','因此，尽管维基百科得益于全球信息的持续更新，但它也对“破坏者”开放。',0,'2026-07-24 13:05:55',NULL),(286,21,16,'Some of the damage is easy to notice.','有些破坏很容易被发现。',0,'2026-07-24 13:05:55',NULL),(287,21,17,'One prankster drew devil horns and a moustache on Microsoft chairman Bill Gate\'s photo, while another edited Greek philosopher Plato\'s biography to say he was a \"Hawaiian weather man.\"','一个恶作剧者在微软董事长比尔·盖茨的照片上画了恶魔角和胡子，另一个人则把希腊哲学家柏拉图的传记改成他是“夏威夷天气预报员”。',0,'2026-07-24 13:05:55',NULL),(288,21,18,'But other things are harder to spot.','但其他问题更难察觉。',0,'2026-07-24 13:05:55',NULL),(289,21,19,'The most common form of vandalism involves adding tiny items of false information into the biography of a famous person.','最常见的破坏形式是在名人传记中添加微小的虚假信息。',0,'2026-07-24 13:05:55',NULL),(290,21,20,'Some of this misinformation has even appeared in newspapers, with The Daily Mail, The Guardian and The Independent all having fallen victim to the pranks.','其中一些虚假信息甚至出现在报纸上，《每日邮报》、《卫报》和《独立报》都曾成为这些恶作剧的受害者。',0,'2026-07-24 13:05:55',NULL),(291,21,21,'For example, in an obituary for British comedian Sir Norman Wisdom, one newspaper claimed that he co-wrote Dame Vera Lynn\'s wartime hit \"There\'ll be Bluebirds over the White Cliffs of Dover.\"','例如，在英国喜剧演员诺曼·威斯登爵士的讣告中，一家报纸声称他与维拉·林恩女爵士合写了战时热门歌曲《白崖上有蓝鸟》。',0,'2026-07-24 13:05:55',NULL),(292,21,22,'He did no such thing.','他根本没做过这种事。',0,'2026-07-24 13:05:55',NULL),(293,21,23,'And in another article, it was reported that TV theme tune composer Ronnie Hazlehurst had written the S Club 7 hit \"Reach.\"','在另一篇文章中，据报道电视主题曲作曲家罗尼·黑泽尔赫斯特创作了S Club 7的热门歌曲《Reach》。',0,'2026-07-24 13:05:55',NULL),(294,21,24,'Once again, not true.','同样，这不是真的。',0,'2026-07-24 13:05:55',NULL),(295,21,25,'So, if you\'re going to use any information from Wikipedia, make sure you double-check it first.','因此，如果你要使用维基百科的任何信息，务必先仔细核实。',0,'2026-07-24 13:05:55',NULL);
/*!40000 ALTER TABLE `article_sentences` ENABLE KEYS */;

--
-- Table structure for table `user_study_logs`
--

DROP TABLE IF EXISTS `user_study_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user_study_logs` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `study_date` date NOT NULL,
  `new_article_count` int(11) NOT NULL DEFAULT '0',
  `review_article_count` int(11) NOT NULL DEFAULT '0',
  `last_active_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_study_date` (`user_id`,`study_date`),
  KEY `idx_study_date` (`study_date`)
) ENGINE=InnoDB AUTO_INCREMENT=184 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_study_logs`
--

/*!40000 ALTER TABLE `user_study_logs` DISABLE KEYS */;
INSERT INTO `user_study_logs` VALUES (1,1,'2026-07-06',0,2,'2026-07-06 16:50:50','2026-07-06 08:49:35',NULL),(3,1,'2026-07-10',0,4,'2026-07-10 06:18:11','2026-07-10 02:45:36',NULL),(7,1,'2026-07-19',0,30,'2026-07-19 15:36:53','2026-07-19 08:10:29',NULL),(37,1,'2026-07-20',5,104,'2026-07-20 23:55:31','2026-07-20 02:06:19',NULL),(146,1,'2026-07-21',1,3,'2026-07-21 10:02:12','2026-07-21 07:25:03',NULL),(150,1,'2026-07-22',0,6,'2026-07-22 04:47:34','2026-07-22 02:21:52',NULL),(156,1,'2026-07-23',5,14,'2026-07-23 16:09:51','2026-07-23 03:58:16',NULL),(175,1,'2026-07-24',1,7,'2026-07-24 14:05:27','2026-07-24 13:05:32',NULL),(183,1,'2026-07-25',0,1,'2026-07-25 11:51:04','2026-07-25 11:51:04',NULL);
/*!40000 ALTER TABLE `user_study_logs` ENABLE KEYS */;

--
-- Table structure for table `article_review_tasks`
--

DROP TABLE IF EXISTS `article_review_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `article_review_tasks` (
  `task_id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `article_id` int(11) NOT NULL,
  `task_type` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'review',
  `scheduled_for` date NOT NULL,
  `status` varchar(16) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending',
  `started_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`task_id`),
  UNIQUE KEY `idx_user_article_day_type` (`user_id`,`article_id`,`scheduled_for`,`task_type`),
  KEY `idx_user_status_schedule` (`user_id`,`status`,`scheduled_for`),
  KEY `idx_user_completed_at` (`user_id`,`completed_at`),
  KEY `fk_article_review_tasks_article` (`article_id`),
  CONSTRAINT `fk_article_review_tasks_article` FOREIGN KEY (`article_id`) REFERENCES `articles` (`article_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_article_review_tasks_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `article_review_tasks`
--

/*!40000 ALTER TABLE `article_review_tasks` DISABLE KEYS */;
INSERT INTO `article_review_tasks` VALUES (3,1,18,'review','2026-07-24','pending',NULL,NULL,'2026-07-23 13:44:36','0000-00-00 00:00:00'),(4,1,19,'review','2026-07-24','pending',NULL,NULL,'2026-07-23 14:12:10','0000-00-00 00:00:00'),(5,1,20,'review','2026-07-24','pending',NULL,NULL,'2026-07-23 14:38:52','0000-00-00 00:00:00'),(6,1,21,'review','2026-07-25','pending',NULL,NULL,'2026-07-24 13:05:55','2026-07-24 13:05:55');
/*!40000 ALTER TABLE `article_review_tasks` ENABLE KEYS */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-07-25 13:29:07
