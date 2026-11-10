/*
 * elan_touch.c - driver do touch ELAN (eKTF2xxx, I2C 0x15) para o
 * Saraiva Lev Neo / Bookeen Cybook Muse FrontLight 2 (Allwinner A13, kernel 3.0.8).
 *
 * Escrito em 2026-11-05 para substituir o elan_touch.ko que falta na rootfs
 * CYBOY4F instalada por engano. Compilado contra o kernel GPL da Bookeen
 * (github.com/BOOKEEN/kernel-linux-3.0, a13_defconfig).
 *
 * Eventos no mesmo formato do driver Goodix da Bookeen (protocolo MT "A"),
 * que e o que o cyevd entende:
 *   toque:  ABS_MT_TOUCH_MAJOR=8 (so no primeiro), ABS_MT_TRACKING_ID=id+1,
 *           ABS_MT_POSITION_X (0..xmax), ABS_MT_POSITION_Y (0..ymax), SYN_MT_REPORT
 *   soltar: ABS_MT_TOUCH_MAJOR=0, SYN_MT_REPORT
 *   sempre: SYN_REPORT
 * Nome do dispositivo de entrada: "elan_ts_d" (listado em /etc/cyevd/association).
 *
 * Parametros (todos em /sys/module/elan_touch/parameters, alteraveis em tempo real):
 *   debug   1 = loga coordenadas brutas e convertidas no dmesg
 *   swap    -1 = automatico (eixo bruto mais longo vira X), 0/1 = forca
 *   invx, invy   inverte o eixo de saida
 *   xmax, ymax   faixa de saida (padrao: ctp_screen_max_x/y do script.bin)
 *   rawx, rawy   maximo bruto de cada eixo (0 = usa a resolucao lida do chip)
 *   pkt     bytes lidos por pacote (padrao 18)
 */

#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/workqueue.h>
#include <linux/io.h>
#include <mach/irqs.h>
#include <mach/sys_config.h>
#include <mach/gpio.h>

#define DRV_NAME	"elan_ts_d"
#define ELAN_ADDR	0x15

#define LEV_PIO_BASE	0x01c20800
#define LEV_PIO_SIZE	0x400

#define CMD_S_PKT	0x52
#define CMD_R_PKT	0x53
#define CMD_W_PKT	0x54
#define HELLO_PKT	0x55
#define TWO_FINGERS_PKT	0x5A
#define FIVE_FINGERS_PKT 0x5D
#define TEN_FINGERS_PKT	0x62
#define MAX_PKT		40

static int debug;
module_param(debug, int, 0644);
static int swap = -1;
module_param(swap, int, 0644);
static int invx = -1;	/* -1 = usa ctp_revert_x_flag do script.bin */
module_param(invx, int, 0644);
static int invy = -1;	/* -1 = usa ctp_revert_y_flag do script.bin */
module_param(invy, int, 0644);
static int xmax;
module_param(xmax, int, 0644);
static int ymax;
module_param(ymax, int, 0644);
static int rawx;
module_param(rawx, int, 0644);
static int rawy;
module_param(rawy, int, 0644);
static int pkt = 18;
module_param(pkt, int, 0644);
static int poll;	/* 1 = forca leitura por varredura (sem interrupcao) */
module_param(poll, int, 0444);

static void __iomem *pio;
static unsigned hdl_rst, hdl_io;
static u32 hdl_eint;
static int int_port = 7, int_pin = 11;	/* PG11 */
static __u32 twi_id = 2;
static int screen_x = 1024, screen_y = 758;
static int s_xchg = -1, s_revx, s_revy;	/* flags do script.bin */

static unsigned short normal_i2c[] = { ELAN_ADDR, I2C_CLIENT_END };

struct elan_data {
	struct i2c_client *client;
	struct input_dev *input;
	struct delayed_work work;
	struct workqueue_struct *wq;
	int res_x, res_y;	/* maximos brutos */
	int touching;
	int irq_ok;		/* 1 = interrupcao, 0 = varredura */
	int stopping;
};

/* ---------- pino de interrupcao (PG11) ---------- */
static int int_level(void)
{
	return (readl(pio + (int_port - 1) * 0x24 + 0x10) >> int_pin) & 1;
}

static int wait_int_low(int ms)
{
	while (ms > 0) {
		if (!int_level())
			return 0;
		msleep(5);
		ms -= 5;
	}
	return -ETIMEDOUT;
}

static void eint_on(int on)
{
	if (hdl_eint)
		sw_gpio_eint_set_enable(hdl_eint, on);
}

/* ---------- conversa com o chip ---------- */
static void elan_reset(void)
{
	if (!hdl_rst)
		return;
	gpio_write_one_pin_value(hdl_rst, 1, "ctp_reset");
	msleep(5);
	gpio_write_one_pin_value(hdl_rst, 0, "ctp_reset");
	msleep(20);
	gpio_write_one_pin_value(hdl_rst, 1, "ctp_reset");
}

static int elan_get(struct i2c_client *c, u8 a, u8 b, u8 cc, u8 d, u8 *buf)
{
	u8 cmd[4] = { a, b, cc, d };
	int rc;

	if (i2c_master_send(c, cmd, 4) != 4)
		return -EIO;
	rc = wait_int_low(300);
	if (rc)
		return rc;
	if (i2c_master_recv(c, buf, 4) != 4)
		return -EIO;
	return buf[0] == CMD_S_PKT ? 0 : -EINVAL;
}

static void elan_identify(struct elan_data *ts)
{
	struct i2c_client *c = ts->client;
	u8 b[4] = { 0 };
	int fw = -1, id = -1, bc = -1, rx = 0, ry = 0;

	if (!elan_get(c, CMD_R_PKT, 0x00, 0x00, 0x01, b))
		fw = (((b[1] & 0x0f) << 4) | ((b[2] & 0xf0) >> 4)) << 8 |
		     (((b[2] & 0x0f) << 4) | ((b[3] & 0xf0) >> 4));
	if (!elan_get(c, CMD_R_PKT, 0xf0, 0x00, 0x01, b))
		id = (((b[1] & 0x0f) << 4) | ((b[2] & 0xf0) >> 4)) << 8 |
		     (((b[2] & 0x0f) << 4) | ((b[3] & 0xf0) >> 4));
	if (!elan_get(c, CMD_R_PKT, 0x01, 0x00, 0x01, b))
		bc = (((b[1] & 0x0f) << 4) | ((b[2] & 0xf0) >> 4)) << 8 |
		     (((b[2] & 0x0f) << 4) | ((b[3] & 0xf0) >> 4));
	if (!elan_get(c, CMD_R_PKT, 0x60, 0x00, 0x00, b))
		rx = b[2] | ((b[3] & 0xf0) << 4);
	if (!elan_get(c, CMD_R_PKT, 0x63, 0x00, 0x00, b))
		ry = b[2] | ((b[3] & 0xf0) << 4);

	pr_info("elan_touch: fw=0x%04x id=0x%04x bootcode=0x%04x res_x=%d res_y=%d\n",
		fw, id, bc, rx, ry);
	/* resolucao em numero de trilhas -> coordenada bruta max = (n-1)*64 */
	if (rx > 0 && rx < 128)
		rx = (rx - 1) * 64;
	if (ry > 0 && ry < 128)
		ry = (ry - 1) * 64;
	ts->res_x = rx > 0 ? rx : 2048;
	ts->res_y = ry > 0 ? ry : 2048;
	pr_info("elan_touch: maximo bruto usado x=%d y=%d\n", ts->res_x, ts->res_y);
}

/* ---------- relatorio de toque ---------- */
static int scale(int v, int vmax, int omax, int inv)
{
	int o;
	if (vmax <= 0)
		vmax = 1;
	if (v < 0)
		v = 0;
	if (v > vmax)
		v = vmax;
	o = v * omax / vmax;
	return inv ? omax - o : o;
}

static void report_point(struct elan_data *ts, int id, int rx, int ry)
{
	int sw, a, amax, b, bmax, x, y;
	int mrx = rawx > 0 ? rawx : ts->res_x;
	int mry = rawy > 0 ? rawy : ts->res_y;
	int ox = xmax > 0 ? xmax : screen_x;
	int oy = ymax > 0 ? ymax : screen_y;

	sw = swap >= 0 ? swap : (s_xchg >= 0 ? s_xchg : (mry > mrx));
	if (sw) {
		a = ry; amax = mry; b = rx; bmax = mrx;
	} else {
		a = rx; amax = mrx; b = ry; bmax = mry;
	}
	x = scale(a, amax, ox, invx >= 0 ? invx : s_revx);
	y = scale(b, bmax, oy, invy >= 0 ? invy : s_revy);

	if (!ts->touching) {
		input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, 8);
		ts->touching = 1;
	}
	input_report_abs(ts->input, ABS_MT_TRACKING_ID, id + 1);
	input_report_abs(ts->input, ABS_MT_POSITION_X, x);
	input_report_abs(ts->input, ABS_MT_POSITION_Y, y);
	input_mt_sync(ts->input);
	if (debug)
		pr_info("elan_touch: id=%d bruto=(%d,%d) tela=(%d,%d)\n",
			id, rx, ry, x, y);
}

static void report_up(struct elan_data *ts)
{
	if (ts->touching) {
		input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, 0);
		input_mt_sync(ts->input);
		ts->touching = 0;
		if (debug)
			pr_info("elan_touch: soltou\n");
	}
}

static void handle_packet(struct elan_data *ts, u8 *buf, int len)
{
	int nf, idx, i, fbits, reported = 0;

	switch (buf[0]) {
	case TWO_FINGERS_PKT:
		nf = 2; fbits = buf[7] & 0x03; idx = 1;
		break;
	case FIVE_FINGERS_PKT:
		nf = 5; fbits = buf[1] >> 3; idx = 2;
		break;
	case TEN_FINGERS_PKT:
		nf = 10; fbits = buf[1] | ((buf[2] & 0x03) << 8); idx = 3;
		break;
	case HELLO_PKT:
		if (debug)
			pr_info("elan_touch: hello %02x %02x %02x %02x\n",
				buf[0], buf[1], buf[2], buf[3]);
		return;
	default:
		if (debug)
			pr_info("elan_touch: pacote desconhecido %02x %02x %02x %02x %02x %02x %02x %02x\n",
				buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7]);
		return;
	}

	for (i = 0; i < nf && idx + 2 < len; i++, idx += 3, fbits >>= 1) {
		int rx, ry;
		if (!(fbits & 1))
			continue;
		rx = ((buf[idx] & 0xf0) << 4) | buf[idx + 1];
		ry = ((buf[idx] & 0x0f) << 8) | buf[idx + 2];
		report_point(ts, i, rx, ry);
		reported++;
		if (reported >= 2)	/* cyevd so acompanha 2 dedos */
			break;
	}
	if (!reported)
		report_up(ts);
	input_sync(ts->input);
}

static int read_packet(struct elan_data *ts)
{
	u8 buf[MAX_PKT];
	int len = pkt > 0 && pkt <= MAX_PKT ? pkt : 18;

	memset(buf, 0, sizeof(buf));
	if (i2c_master_recv(ts->client, buf, len) != len) {
		if (debug)
			pr_info("elan_touch: falha de leitura i2c\n");
		return -EIO;
	}
	if (debug > 1)
		pr_info("elan_touch: pkt %02x %02x %02x %02x %02x %02x %02x %02x\n",
			buf[0], buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7]);
	if (buf[0] == 0x00 || buf[0] == 0xff)
		return 0;
	handle_packet(ts, buf, len);
	return 0;
}

static void elan_work(struct work_struct *w)
{
	struct elan_data *ts = container_of(to_delayed_work(w), struct elan_data, work);
	int n;

	if (ts->irq_ok) {
		read_packet(ts);
		sw_gpio_eint_clr_irqpd_sta(hdl_eint);
		eint_on(1);
		return;
	}
	/* modo varredura: INT (PG11) e entrada simples, baixo = pacote pronto */
	for (n = 0; n < 4 && !int_level(); n++)
		read_packet(ts);
	if (!ts->stopping)
		queue_delayed_work(ts->wq, &ts->work, msecs_to_jiffies(15));
}

static irqreturn_t elan_irq(int irq, void *dev_id)
{
	struct elan_data *ts = dev_id;

	if (!hdl_eint || sw_gpio_eint_get_irqpd_sta(hdl_eint) != 1)
		return IRQ_NONE;
	eint_on(0);
	sw_gpio_eint_clr_irqpd_sta(hdl_eint);
	queue_delayed_work(ts->wq, &ts->work, 0);
	return IRQ_HANDLED;
}

static int setup_irq_mode(struct elan_data *ts)
{
	static const unsigned long tries[] = {
		IRQF_SHARED | IRQF_TRIGGER_RISING,
		IRQF_SHARED | IRQF_TRIGGER_FALLING,
		IRQF_SHARED,
		IRQF_SHARED | IRQF_TRIGGER_RISING | IRQF_TRIGGER_FALLING,
	};
	int i, err = -ENODEV;

	hdl_eint = sw_gpio_irq_request("ctp_para", "ctp_int_port", TRIG_LEVL_LOW);
	if (!hdl_eint || hdl_eint == (u32)-1) {
		hdl_eint = 0;
		pr_err("elan_touch: sw_gpio_irq_request falhou\n");
		return -ENODEV;
	}
	for (i = 0; i < ARRAY_SIZE(tries); i++) {
		err = request_irq(SW_INT_IRQNO_PIO, elan_irq, tries[i], DRV_NAME, ts);
		if (!err) {
			pr_info("elan_touch: interrupcao ok (flags 0x%lx)\n", tries[i]);
			sw_gpio_eint_clr_irqpd_sta(hdl_eint);
			eint_on(1);
			return 0;
		}
	}
	pr_err("elan_touch: request_irq falhou (%d)\n", err);
	sw_gpio_irq_free(hdl_eint);
	hdl_eint = 0;
	return err;
}

/* ---------- i2c ---------- */
static int elan_detect(struct i2c_client *client, struct i2c_board_info *info)
{
	if (client->adapter->nr != twi_id)
		return -ENODEV;
	strlcpy(info->type, DRV_NAME, I2C_NAME_SIZE);
	return 0;
}

static int elan_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
	struct elan_data *ts;
	u8 hello[4] = { 0 };
	int err;

	ts = kzalloc(sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->client = client;
	i2c_set_clientdata(client, ts);

	/* fase de identificacao: PG11 como entrada simples */
	hdl_io = gpio_request_ex("ctp_para", "ctp_io_port");
	pr_info("elan_touch: probe em %d-%04x, int antes do reset=%d\n",
		client->adapter->nr, client->addr, int_level());
	elan_reset();
	if (!wait_int_low(1500)) {
		i2c_master_recv(client, hello, 4);
		pr_info("elan_touch: hello %02x %02x %02x %02x\n",
			hello[0], hello[1], hello[2], hello[3]);
	} else {
		pr_info("elan_touch: sem hello apos reset (int=%d)\n", int_level());
	}
	msleep(10);
	elan_identify(ts);

	ts->input = input_allocate_device();
	if (!ts->input) {
		err = -ENOMEM;
		goto fail;
	}
	ts->input->name = DRV_NAME;
	ts->input->id.bustype = BUS_I2C;
	ts->input->dev.parent = &client->dev;
	__set_bit(EV_SYN, ts->input->evbit);
	__set_bit(EV_ABS, ts->input->evbit);
	__set_bit(EV_KEY, ts->input->evbit);
	__set_bit(BTN_TOUCH, ts->input->keybit);
	input_set_abs_params(ts->input, ABS_MT_POSITION_X, 0,
			     xmax > 0 ? xmax : screen_x, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_POSITION_Y, 0,
			     ymax > 0 ? ymax : screen_y, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_WIDTH_MAJOR, 0, 255, 0, 0);
	input_set_abs_params(ts->input, ABS_MT_TRACKING_ID, 0, 255, 0, 0);
	err = input_register_device(ts->input);
	if (err) {
		input_free_device(ts->input);
		goto fail;
	}

	ts->wq = create_singlethread_workqueue("elan_touch");
	INIT_DELAYED_WORK(&ts->work, elan_work);

	if (!poll) {
		if (hdl_io) {
			gpio_release(hdl_io, 2);
			hdl_io = 0;
		}
		ts->irq_ok = setup_irq_mode(ts) == 0;
		if (!ts->irq_ok)	/* volta PG11 para entrada simples */
			hdl_io = gpio_request_ex("ctp_para", "ctp_io_port");
	}
	if (!ts->irq_ok) {
		pr_info("elan_touch: usando varredura a cada 15 ms\n");
		queue_delayed_work(ts->wq, &ts->work, msecs_to_jiffies(15));
	}
	pr_info("elan_touch: pronto (\"%s\", %s, saida %dx%d, swap=%d invx=%d invy=%d)\n",
		DRV_NAME, ts->irq_ok ? "interrupcao" : "varredura",
		xmax > 0 ? xmax : screen_x, ymax > 0 ? ymax : screen_y,
		swap, invx, invy);
	return 0;

fail:
	kfree(ts);
	return err;
}

static int elan_remove(struct i2c_client *client)
{
	struct elan_data *ts = i2c_get_clientdata(client);

	ts->stopping = 1;
	eint_on(0);
	if (ts->irq_ok)
		free_irq(SW_INT_IRQNO_PIO, ts);
	cancel_delayed_work_sync(&ts->work);
	destroy_workqueue(ts->wq);
	if (hdl_eint) {
		sw_gpio_irq_free(hdl_eint);
		hdl_eint = 0;
	}
	if (hdl_io) {
		gpio_release(hdl_io, 2);
		hdl_io = 0;
	}
	input_unregister_device(ts->input);
	kfree(ts);
	return 0;
}

static int elan_suspend(struct i2c_client *client, pm_message_t mesg)
{
	eint_on(0);
	return 0;
}

static int elan_resume(struct i2c_client *client)
{
	struct elan_data *ts = i2c_get_clientdata(client);

	ts->touching = 0;
	if (hdl_eint) {
		sw_gpio_eint_set_trigtype(hdl_eint, TRIG_LEVL_LOW);
		sw_gpio_eint_clr_irqpd_sta(hdl_eint);
		eint_on(1);
	}
	return 0;
}

static const struct i2c_device_id elan_id[] = {
	{ DRV_NAME, 0 },
	{ }
};

static struct i2c_driver elan_driver = {
	.class		= I2C_CLASS_HWMON,
	.driver		= {
		.name	= DRV_NAME,
		.owner	= THIS_MODULE,
	},
	.probe		= elan_probe,
	.remove		= elan_remove,
	.suspend	= elan_suspend,
	.resume		= elan_resume,
	.id_table	= elan_id,
	.detect		= elan_detect,
	.address_list	= normal_i2c,
};

static int __init elan_init(void)
{
	int used = 0, v;
	user_gpio_set_t st;
	unsigned h;

	if (script_parser_fetch("ctp_para", "ctp_used", &used, 1) || used != 1) {
		pr_err("elan_touch: ctp_used != 1\n");
		return -ENODEV;
	}
	script_parser_fetch("ctp_para", "ctp_twi_id", (int *)&twi_id, 1);
	if (!script_parser_fetch("ctp_para", "ctp_screen_max_x", &v, 1) && v > 0)
		screen_x = v;
	if (!script_parser_fetch("ctp_para", "ctp_screen_max_y", &v, 1) && v > 0)
		screen_y = v;
	if (!script_parser_fetch("ctp_para", "ctp_exchange_x_y_flag", &v, 1))
		s_xchg = v ? 1 : 0;
	if (!script_parser_fetch("ctp_para", "ctp_revert_x_flag", &v, 1))
		s_revx = v ? 1 : 0;
	if (!script_parser_fetch("ctp_para", "ctp_revert_y_flag", &v, 1))
		s_revy = v ? 1 : 0;

	pio = ioremap(LEV_PIO_BASE, LEV_PIO_SIZE);
	if (!pio)
		return -EIO;

	hdl_rst = gpio_request_ex("ctp_para", "ctp_reset");
	h = gpio_request_ex("ctp_para", "ctp_io_port");
	if (h) {
		memset(&st, 0, sizeof(st));
		if (!gpio_get_one_pin_status(h, &st, "ctp_io_port", 1)) {
			int_port = st.port;
			int_pin = st.port_num;
		}
		gpio_release(h, 2);
	}
	pr_info("elan_touch: twi=%d tela=%dx%d reset=%s int=P%c%d troca=%d inv_x=%d inv_y=%d\n",
		twi_id, screen_x, screen_y, hdl_rst ? "ok" : "FALTA",
		'A' + int_port - 1, int_pin, s_xchg, s_revx, s_revy);
	return i2c_add_driver(&elan_driver);
}

static void __exit elan_exit(void)
{
	i2c_del_driver(&elan_driver);
	if (hdl_rst)
		gpio_release(hdl_rst, 2);
	if (pio)
		iounmap(pio);
}

module_init(elan_init);
module_exit(elan_exit);
MODULE_DESCRIPTION("ELAN touch para Lev Neo (A13)");
MODULE_LICENSE("GPL");
