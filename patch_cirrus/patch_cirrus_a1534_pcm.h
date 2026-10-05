static int cs_4208_playback_pcm_prepare(struct hda_pcm_stream *hinfo,
					struct hda_codec *codec,
					unsigned int stream_tag,
					unsigned int format,
					struct snd_pcm_substream *substream)
{
	codec_info(codec, "MB81 HP PREPARE: stream_tag=%d format=0x%x\n",
		   stream_tag, format);

	/* Headphones only: DAC 0x02, 2ch */
	snd_hda_codec_setup_stream(codec, 0x02, stream_tag, 0, format);

	return 0;
}

static int cs_4208_playback_pcm_cleanup(struct hda_pcm_stream *hinfo,
					struct hda_codec *codec,
					struct snd_pcm_substream *substream)
{
	codec_info(codec, "MB81 HP CLEANUP\n");
	snd_hda_codec_cleanup_stream(codec, 0x02);
	return 0;
}

// this is very hacky but until get more understanding of what we can do with the 4208 setup
// re-define these from hda_codec.c here
// NOTA BENE - need to check this is consistent with any hda_codec.c updates!!

/*
 * audio-converter setup caches
 */
struct hda_cvt_setup {
	hda_nid_t nid;
	u8 stream_tag;
	u8 channel_id;
	u16 format_id;
	unsigned char active;   /* cvt is currently used */
	unsigned char dirty;    /* setups should be cleared */
};
/* get or create a cache entry for the given audio converter NID */
static struct hda_cvt_setup *
get_hda_cvt_setup_4208(struct hda_codec *codec, hda_nid_t nid)
{
	struct hda_cvt_setup *p;
	int i;

	for (i = 0; i < codec->cvt_setups.used; i++) {
		p = snd_array_elem(&codec->cvt_setups, i);
		if (p->nid == nid)
			return p;
	}
	p = snd_array_new(&codec->cvt_setups);
	if (p)
		p->nid = nid;
	return p;
}

static int cs_4208_playback_pcm_open(struct hda_pcm_stream *hinfo,
				     struct hda_codec *codec,
				     struct snd_pcm_substream *substream)
{
	codec_info(codec, "MB81 HP OPEN\n");
	/* Headphones only — no TDM/speaker setup here */
	return 0;
}

static const struct hda_pcm_stream cs4208_pcm_analog_playback = {
	.substreams = 1,
	.channels_min = 2,
	.channels_max = 2,
	.rates = SNDRV_PCM_RATE_44100 | SNDRV_PCM_RATE_48000,
	.formats = SNDRV_PCM_FMTBIT_S16_LE,
	.maxbps = 16,
	.nid = 0x02,
	.ops = {
		.open = cs_4208_playback_pcm_open,
		.prepare = cs_4208_playback_pcm_prepare,
		.cleanup = cs_4208_playback_pcm_cleanup,
	},
};

/* TDM speaker PCM — separate stream for converter 0x0a */
static int cs_4208_tdm_pcm_open(struct hda_pcm_stream *hinfo,
				struct hda_codec *codec,
				struct snd_pcm_substream *substream)
{
	codec_info(codec, "MB81 TDM OPEN\n");
	/* Don't call play_macbook81() here — its coeff writes
	 * poison the verb cache, preventing prepare from updating
	 * coefficients 0x00, 0x01, 0x36 to TDM-active values. */
	return 0;
}

static int cs_4208_tdm_pcm_prepare(struct hda_pcm_stream *hinfo,
				   struct hda_codec *codec,
				   unsigned int stream_tag,
				   unsigned int format,
				   struct snd_pcm_substream *substream)
{
	unsigned int tdm_fmt = (format & 0xfff0) | 0x03; /* force 4ch */
	unsigned int tdm_en;

	codec_info(codec, "MB81 TDM PREPARE: stream_tag=%d format=0x%x\n",
		   stream_tag, format);

	/*
	 * Mirror the proven driverless efi_recover.py replay_regs() + chime
	 * playback sequence:
	 *   0x0a -> D0 ; SET_CHANNEL_STREAMID + SET_STREAM_FORMAT (once) ;
	 *   SET_CVT_CHAN_COUNT = 4ch ; replay the gated amp coef image ;
	 *   pin 0x1d -> OUT ; TDM_EN = 1.
	 *
	 * The old converter "sync dance" (SET_STREAM_FORMAT 0x0a -> 0,
	 * coef 0x01 |= 0x100, then restore the format) momentarily disabled the
	 * converter mid-bring-up and de-synced the CS4208 TDM serializer into a
	 * silent state no register replay could undo. efi_recover.py plays sound
	 * without ever zeroing the format or poking coef 0x01 — so it is dropped;
	 * the format is written exactly once.
	 */
	snd_hda_codec_write(codec, 0x0a, 0, AC_VERB_SET_POWER_STATE, AC_PWRST_D0);
	snd_hda_codec_setup_stream(codec, 0x0a, stream_tag, 0, tdm_fmt);

	/*
	 * snd_hda_codec_setup_stream() only writes stream tag + format; the
	 * CS4208 TDM serializer also needs the explicit channel-count verb
	 * (efi_recover.py: verb(0x0a, 0x72d, 0x03)).
	 */
	snd_hda_codec_write(codec, 0x0a, 0, AC_VERB_SET_CVT_CHAN_COUNT, 0x03);

	/*
	 * Re-apply the full EFI gated coefficient image (the class-D amp config,
	 * 0x41-0x6b). cs4208_coef_init_verbs + snd_hda_gen_init disturb this
	 * block during bring-up and play_macbook81() restored only 0x50 —
	 * leaving every visible register correct (coef 0x1f=0x0, tdm_en=1,
	 * format 0x4013, GPIO0 high, DMA advancing) but the amp silent.
	 * Replaying it here, right before the stream starts, mirrors
	 * efi_recover.py's replay_regs() minus its D3hot->D0 cycle and survives
	 * any codec re-init / runtime-PM cycle.
	 */
	mb81_apply_software_workarounds(codec);

	snd_hda_codec_write(codec, 0x1d, 0,
			    AC_VERB_SET_PIN_WIDGET_CONTROL, PIN_OUT);
	/* Re-enable TDM output bus (cleared by clearRegisters during init). */
	snd_hda_codec_write(codec, CS4208_VENDOR_NID, 0,
			    CS4208_VERB_SET_TDM_ENABLE, 1);

	tdm_en = snd_hda_codec_read(codec, CS4208_VENDOR_NID, 0,
				    CS4208_VERB_GET_TDM_ENABLE, 0);
	codec_info(codec, "MB81 TDM PREPARE done: tdm_en=0x%x format=0x%x\n",
		   tdm_en, tdm_fmt);
	return 0;
}

static int cs_4208_tdm_pcm_cleanup(struct hda_pcm_stream *hinfo,
				   struct hda_codec *codec,
				   struct snd_pcm_substream *substream)
{
	codec_info(codec, "MB81 TDM CLEANUP\n");
	/* Don't tear down — cleanup kills state needed for next play */
	snd_hda_codec_cleanup_stream(codec, 0x0a);
	return 0;
}

static const struct hda_pcm_stream cs4208_pcm_tdm_playback = {
	.substreams = 1,
	.channels_min = 2,
	.channels_max = 4,
	/* 44.1k ONLY: EFI's entire clock/coef image is configured for 44.1kHz
	 * (working converter format 0x4013). Allowing 48k let PipeWire open the
	 * converter at 0x0013, diverging from the proven EFI state. */
	.rates = SNDRV_PCM_RATE_44100,
	.formats = SNDRV_PCM_FMTBIT_S16_LE,
	.maxbps = 16,
	.nid = 0x0a, /* TDM converter — DMA routes directly */
	.ops = {
		.open = cs_4208_tdm_pcm_open,
		.prepare = cs_4208_tdm_pcm_prepare,
		.cleanup = cs_4208_tdm_pcm_cleanup,
	},
};

static void cs_4208_fill_pcm_stream_name(char *str, size_t len, const char *sfx,
					 const char *chip_name)
{
	char *p;

	if (*str)
		return;
	strscpy(str, chip_name, len);

	/* drop non-alnum chars after a space */
	for (p = strchr(str, ' '); p; p = strchr(p + 1, ' ')) {
		if (!isalnum(p[1])) {
			*p = 0;
			break;
		}
	}
	strscpy(str, sfx, len);
}

void cs_4208_playback_pcm_hook(struct hda_pcm_stream *hinfo,
			       struct hda_codec *codec,
			       struct snd_pcm_substream *substream, int action)
{
	if (action == HDA_GEN_PCM_ACT_OPEN)
		play_a1534(codec);
}

static int cs_4208_build_controls_explicit(struct hda_codec *codec)
{
	codec_dbg(codec, "cs_4208_build_controls_explicit start");
	codec_dbg(codec, "cs_4208_build_controls_explicit end");
	return 0;
}

int cs_4208_build_pcms_explicit(struct hda_codec *codec)
{
	struct cs_spec *spec = codec->spec;
	struct hda_gen_spec *gen_spec = &(spec->gen);
	struct hda_pcm *info;

	codec_dbg(codec, "cs_4208_build_pcms_explicit start");

	/* PCM 0: Headphone analog output via DAC 0x02 */
	info = snd_hda_codec_pcm_new(codec, "CS4208 Analog");
	if (!info)
		return -ENOMEM;
	gen_spec->pcm_rec[0] = info;

	info->stream[SNDRV_PCM_STREAM_PLAYBACK] = cs4208_pcm_analog_playback;
	info->stream[SNDRV_PCM_STREAM_PLAYBACK].nid = 0x02;
	info->stream[SNDRV_PCM_STREAM_PLAYBACK].channels_max = 2;
	info->pcm_type = HDA_PCM_TYPE_AUDIO;

	codec_dbg(codec, "cs_4208_build_pcms_explicit end");
	return 0;
}

/*
void cs_4208_jack_unsol_event(struct hda_codec *codec, unsigned int res)
{
	struct hda_jack_tbl *event;
	int tag = (res >> AC_UNSOL_RES_TAG_SHIFT) & 0x7f;

	dev_info(hda_codec_dev(codec), "cs_4208_jack_unsol_event 0x%08x tag 0x%02x\n",res,tag);

	event = snd_hda_jack_tbl_get_from_tag(codec, tag, 0);
        if (!event)
		return;
	event->jack_dirty = 1;

	//call_jack_callback(codec, event);
	snd_hda_jack_report_sync(codec);
}
*/

#define cs_4208_free            snd_hda_gen_free

static int cs_4208_init_explicit(struct hda_codec *codec)
{
	//struct cs_spec *spec = codec->spec;
	codec_dbg(codec, "cs_4208_init_explicit start");
	codec_dbg(codec, "cs_4208_init_explicit end");

	return 0;
}

static void cs_4208_free_explicit(struct hda_codec *codec)
{
	kfree(codec->spec);
}

// real def is CONFIG_PM
static const struct hda_codec_ops cs_4208_patch_ops_explicit = {
	.build_controls = cs_4208_build_controls_explicit,
	.build_pcms = cs_4208_build_pcms_explicit,
	.init = cs_4208_init_explicit,
	.remove = cs_4208_free_explicit,
	//.unsol_event = snd_hda_jack_unsol_event, //cs_4208_jack_unsol_event,
//#ifdef UNDEF_CONFIG_PM
//      .suspend = cs_4208_suspend,
//      .resume = cs_4208_resume,
//#endif
};
